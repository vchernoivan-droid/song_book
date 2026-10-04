import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../models/song.dart';
import '../models/song_defaults.dart';
import '../services/auto_scroll.dart';
import '../services/lyric_locator.dart';
import '../services/song_listen_logger.dart';
import '../services/song_parser.dart';
import '../services/song_storage.dart';
import 'song_editor_screen.dart';

/// Экран просмотра текста песни (моноширинный шрифт).
///
/// Сохранённое транспонирование применяется автоматически; кнопками в AppBar
/// сдвигаем его на полтона, текущее значение пишется прямо в файл песни.
class SongDetailScreen extends StatefulWidget {
  final Song song;
  final SongListenLoggerFactory? listenLoggerFactory;
  const SongDetailScreen({
    super.key,
    required this.song,
    this.listenLoggerFactory,
  });

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen>
    with SingleTickerProviderStateMixin {
  final _storage = SongStorage();
  late Song _song = widget.song;
  late int _semitones = ((_song.transpose % 12) + 12) % 12;
  late int _fontSize = _song.fontSize;
  Future<void> _persistChain = Future.value();

  final _scrollCtrl = ScrollController();
  bool _autoScroll = false;
  bool _pausedByDrag = false;
  int _countdown = 0;
  SongListenLogger? _recorder;
  LyricLocator? _locator;
  final _singerLine = ValueNotifier<int?>(null);
  int? _matchedLine;
  Timer? _silenceTimer;
  static const double _pursuitTau = 3.0;
  double _pursuitTarget = 0;
  bool _suppressSettle = false;
  Duration? _pursuitLastElapsed;
  late final Ticker _pursuit = createTicker(_pursuitTick);
  late ({String text, List<double> tops, List<double> textCenters, List<({int start, int end})> ranges, double totalHeight})
      _layout;
  final _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _refreshLayout();
  }

  @override
  void dispose() {
    _pursuit.dispose();
    _resetSinger();
    _recorder?.stop();
    _recorder = null;
    _scrollCtrl.dispose();
    _singerLine.dispose();
    super.dispose();
  }

  // Единственное представление: просмотр и сохранение работают с ним.
  ParsedSong get _transposedSong =>
      parseSong(_song.content).transposed(_semitones);

  void _refreshLayout() {
    final rendered = renderSongLines(_transposedSong);
    final lineHeight = _fontSize * 1.35;
    _layout = (
      text: rendered.text,
      tops: lineTops(
        text: rendered.text,
        ranges: rendered.lines,
        lineHeight: lineHeight,
      ),
      textCenters: lineTextCenters(
        text: rendered.text,
        ranges: rendered.lines,
        lineHeight: lineHeight,
      ),
      ranges: rendered.lines,
      totalHeight: '\n'.allMatches(rendered.text).length * lineHeight,
    );
    _locator = LyricLocator(_transposedSong);
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasureRows());
  }

  void _remeasureRows() {
    if (!mounted) return;
    final root = _textKey.currentContext?.findRenderObject();
    if (root == null) return;
    RenderEditable? editable;
    void visit(RenderObject ro) {
      if (editable != null) return;
      if (ro is RenderEditable) {
        editable = ro;
        return;
      }
      ro.visitChildren(visit);
    }

    visit(root);
    final re = editable;
    if (re == null) return;
    final ranges = _layout.ranges;
    final tops = List<double>.filled(ranges.length, 0);
    final centers = List<double>.filled(ranges.length, 0);
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final boxes = re.getBoxesForSelection(
        TextSelection(baseOffset: r.start, extentOffset: r.end),
      );
      if (boxes.isEmpty) {
        tops[i] = _layout.tops[i];
        centers[i] = _layout.textCenters[i];
        continue;
      }
      tops[i] = boxes.first.top;
      centers[i] = (boxes.last.top + boxes.last.bottom) / 2;
    }
    setState(() {
      _layout = (
        text: _layout.text,
        tops: tops,
        textCenters: centers,
        ranges: ranges,
        totalHeight: re.size.height,
      );
    });
  }

  Future<void> _edit() async {
    // Редактор открываем ровно с тем текстом, что на экране: сохранится
    // он как есть, шапка транспонирования не пишется (transpose = 0).
    final editing = _song.copyWith(content: _layout.text, transpose: 0);
    final updated = await Navigator.of(context).push<Song?>(
      MaterialPageRoute(builder: (_) => SongEditorScreen(song: editing)),
    );
    if (updated != null && mounted) {
      setState(() {
        _song = updated;
        _semitones = updated.transpose;
        _fontSize = updated.fontSize;
        _refreshLayout();
      });
    }
  }

  void _shiftTo(int value) {
    final v = ((value % 12) + 12) % 12;
    if (v == _semitones) return;
    setState(() {
      _semitones = v;
      _refreshLayout();
    });
    _persist(v, _fontSize);
  }

  void _setFontSize(int value) {
    final v = value.clamp(10, 28);
    if (v == _fontSize) return;
    setState(() {
      _fontSize = v;
      _refreshLayout();
    });
    _persist(_semitones, v);
  }

  void _persist(int semitones, int fontSize) {
    // Быстрые нажатия не должны гоняться за файловой записью.
    _persistChain = _persistChain.then((_) async {
      try {
        final name = await _storage.writeSong(
          desiredTitle: _song.title,
          content: Song.withHeaders(
            fontSize: fontSize,
            body: renderSong(parseSong(_song.content).transposed(semitones)),
          ),
          oldFileName: _song.fileName,
        );
        _song = _song.copyWith(
          fileName: name,
          transpose: 0,
          fontSize: fontSize,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить настройки')),
          );
        }
      }
    });
  }

  double _posForY(double y) {
    final tops = _layout.tops;
    if (tops.isEmpty) return 0;
    if (y <= tops.first) return 0;
    final last = tops.length - 1;
    if (y >= _layout.totalHeight) return tops.length.toDouble();
    if (y >= tops[last]) {
      return last + (y - tops[last]) / (_layout.totalHeight - tops[last]);
    }
    for (var k = 0; k < last; k++) {
      if (y >= tops[k] && y <= tops[k + 1]) {
        return k + (y - tops[k]) / (tops[k + 1] - tops[k]);
      }
    }
    return last.toDouble();
  }

  void _scrollToSinger() {
    if (!mounted ||
        _countdown > 0 ||
        !_autoScroll ||
        _pausedByDrag ||
        !_scrollCtrl.hasClients) {
      return;
    }
    final line = _singerLine.value;
    if (line == null || line >= _layout.textCenters.length) return;
    final raw = _layout.textCenters[line] +
        16 -
        _scrollCtrl.position.viewportDimension * 0.4;
    final max = _scrollCtrl.position.maxScrollExtent;
    _pursuitTarget = raw < 0 ? 0.0 : (raw > max ? max : raw);
    _ensurePursuit();
  }

  void _ensurePursuit() {
    if (!mounted || !_autoScroll || _pausedByDrag) return;
    if (!_pursuit.isActive) {
      _pursuitLastElapsed = null;
      _pursuit.start();
    }
  }

  void _pursuitTick(Duration elapsed) {
    final dt = _pursuitLastElapsed == null
        ? Duration.zero
        : elapsed - _pursuitLastElapsed!;
    _pursuitLastElapsed = elapsed;
    if (!mounted || !_autoScroll || _pausedByDrag || !_scrollCtrl.hasClients) {
      _pursuit.stop();
      return;
    }
    final delta = _pursuitTarget - _scrollCtrl.offset;
    if (delta.abs() < 4.0) {
      if (delta.abs() > 0.1) {
        _applyJump(_scrollCtrl.offset + delta);
      }
      _pursuit.stop();
      return;
    }
    final secs = dt.inMicroseconds / 1e6;
    final step = delta * (1 - math.exp(-secs / _pursuitTau));
    if (step.abs() < 0.05) return;
    _applyJump(_scrollCtrl.offset + step);
  }

  void _applyJump(double value) {
    _suppressSettle = true;
    _scrollCtrl.jumpTo(value);
    _suppressSettle = false;
  }

  Future<void> _startAutoScroll() async {
    _resetSinger();
    setState(() {
      _autoScroll = true;
      _pausedByDrag = false;
      _countdown = 3;
    });
    unawaited(_startRecording());
    while (_countdown > 0 && mounted && _autoScroll) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_autoScroll) return;
      setState(() => _countdown = _countdown - 1);
    }
    if (!mounted || !_autoScroll) return;
    _recorder?.note('countdown-end');
    if (_layout.tops.isEmpty) {
      _stopAutoScroll();
    }
  }

  Future<void> _startRecording() async {
    final logger = (widget.listenLoggerFactory ?? SongListenLogger.new)(
      title: _song.title,
      fontSize: _fontSize,
      localeId: SongListenLogger.localeIdFor(_song.content),
      position: () {
        if (!_scrollCtrl.hasClients) return 0.0;
        return _posForY(_scrollCtrl.offset +
            _scrollCtrl.position.viewportDimension * 0.4 -
            16);
      },
      onResult: _onRecognized,
    );
    _recorder = logger;
    bool ok;
    try {
      ok = await logger.start();
    } catch (e) {
      debugPrint('STT start failed: $e');
      ok = false;
    }
    if (!ok) {
      if (identical(_recorder, logger)) _recorder = null;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Микрофон недоступен — без записи')),
        );
      }
      return;
    }
    if (mounted) setState(() {});
  }

  void _onRecognized(String words) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 15), _onSilenceTimeout);
    final current = _matchedLine;
    final line =
        _locator?.locate(LyricLocator.keysOf(words), previousLine: current);
    if (line == null || line == current) return;
    _matchedLine = line;
    _singerLine.value = line;
    _recorder?.note('match:$line');
    _scrollToSinger();
  }

  void _resetSinger() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _matchedLine = null;
    _singerLine.value = null;
  }

  void _onSilenceTimeout() {
    _resetSinger();
    _recorder?.note('silence-reset');
  }

  void _pauseAutoScroll() {
    if (_pausedByDrag) return;
    _pausedByDrag = true;
    _pursuit.stop();
    _recorder?.note('auto-pause');
  }

  void _settleAfterUserScroll() {
    if (!mounted || !_autoScroll || _countdown > 0 || !_scrollCtrl.hasClients) {
      return;
    }
    final wasPaused = _pausedByDrag;
    _pausedByDrag = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final before = _singerLine.value;
    _snapSingerTo(_scrollCtrl.position.viewportDimension * 0.4);
    if (_singerLine.value != before) {
      _recorder?.note('manual:$_matchedLine');
    }
    if (wasPaused) {
      _recorder?.note('auto-resume');
    }
    _scrollToSinger();
  }

  void _snapSingerTo(double screenY) {
    if (!_scrollCtrl.hasClients || _layout.tops.isEmpty) return;
    final contentY = screenY - 16 + _scrollCtrl.offset;
    final centers = _layout.textCenters;
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final d = (contentY - centers[i]).abs();
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    _matchedLine = nearest;
    _singerLine.value = nearest;
  }

  void _onGutterTap(double screenY) {
    if (_countdown > 0) return;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final before = _singerLine.value;
    _snapSingerTo(screenY);
    if (_singerLine.value != before) {
      _recorder?.note('manual:$_matchedLine');
    }
    _scrollToSinger();
  }

  Color _countdownColor() {
    if (_countdown >= 3) return Colors.red.shade600;
    if (_countdown == 2) return Colors.amber.shade900;
    return Colors.green.shade600;
  }

  void _stopAutoScroll() {
    _resetSinger();
    _pausedByDrag = false;
    _pursuit.stop();
    _recorder?.stop();
    _recorder = null;
    if (mounted) {
      setState(() {
        _autoScroll = false;
        _countdown = 0;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить песню?'),
        content: Text('«${_song.title}» будет удалена безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _storage.deleteSong(_song.fileName);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _buildAutoScrollBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            if (_recorder != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 2),
                child: Tooltip(
                  message: 'Идёт запись таймингов',
                  child: Icon(
                    Icons.fiber_manual_record,
                    size: 16,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            IconButton(
              tooltip: _autoScroll ? 'Пауза' : 'Автоскролл',
              visualDensity: VisualDensity.compact,
              icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                if (_autoScroll) {
                  _stopAutoScroll();
                } else {
                  _startAutoScroll();
                }
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AnimatedBuilder(
                  animation: _scrollCtrl,
                  builder: (_, _) {
                    final pos = _scrollCtrl.hasClients
                        ? _scrollCtrl.position
                        : null;
                    if (pos == null || !pos.hasContentDimensions) {
                      return const LinearProgressIndicator(value: 0);
                    }
                    final max = pos.maxScrollExtent;
                    final value = max <= 0
                        ? 0.0
                        : (pos.pixels / max).clamp(0.0, 1.0);
                    return LinearProgressIndicator(value: value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'Roboto Mono',
      fontSize: _fontSize.toDouble(),
      height: 1.35,
    );
    final text = _song.content.isEmpty ? '(пусто)' : _layout.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(_song.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Уменьшить шрифт',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            onPressed: () => _setFontSize(_fontSize - 1),
          ),
          Container(
            width: 36,
            alignment: Alignment.center,
            child: Text(
              '$_fontSize',
              style: TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                color: _fontSize == defaultFontSize
                    ? null
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Увеличить шрифт',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () => _setFontSize(_fontSize + 1),
          ),
          IconButton(
            tooltip: 'На полтона ниже',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => _shiftTo(_semitones - 1),
          ),
          IconButton(
            tooltip: 'На полтона выше',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => _shiftTo(_semitones + 1),
          ),
          IconButton(
            tooltip: 'Редактировать',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification &&
                        n.dragDetails != null &&
                        _autoScroll) {
                      if (_countdown == 0) {
                        _pauseAutoScroll();
                      } else {
                        _stopAutoScroll();
                      }
                    } else if (n is ScrollEndNotification && !_suppressSettle) {
                      _settleAfterUserScroll();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(48, 16, 16, 32),
                    child: SelectableText(text, key: _textKey, style: mono),
                  ),
                ),
                if (_autoScroll)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_scrollCtrl, _singerLine]),
                        builder: (_, _) {
                          if (!_scrollCtrl.hasClients) {
                            return const SizedBox.shrink();
                          }
                          final singerLine = _singerLine.value;
                          if (singerLine == null) {
                            return const SizedBox.shrink();
                          }
                          final screenY = _layout.textCenters[singerLine] +
                              16 -
                              _scrollCtrl.offset;
                          return CustomPaint(
                            painter: _CursorPainter(
                              screenY,
                              Colors.green.shade800,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_autoScroll)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 48,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (d) => _onGutterTap(d.localPosition.dy),
                    ),
                  ),
                if (_countdown > 0)
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _countdownColor(),
                          width: 3,
                        ),
                      ),
                      child: Text(
                        '$_countdown',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: _countdownColor(),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildAutoScrollBar(),
        ],
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final double y;
  final Color color;

  _CursorPainter(this.y, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(30, y)
      ..lineTo(10, y - 12)
      ..lineTo(10, y + 12)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) =>
      oldDelegate.y != y || oldDelegate.color != color;
}
