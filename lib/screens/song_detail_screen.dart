import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/song.dart';
import '../models/song_defaults.dart';
import '../services/auto_scroll.dart';
import '../services/song_parser.dart';
import '../services/song_storage.dart';
import 'song_editor_screen.dart';

/// Экран просмотра текста песни (моноширинный шрифт).
///
/// Сохранённое транспонирование применяется автоматически; кнопками в AppBar
/// сдвигаем его на полтона, текущее значение пишется прямо в файл песни.
class SongDetailScreen extends StatefulWidget {
  final Song song;
  const SongDetailScreen({super.key, required this.song});

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen>
    with SingleTickerProviderStateMixin {
  final _storage = SongStorage();
  late Song _song = widget.song;
  late int _semitones = ((_song.transpose % 12) + 12) % 12;
  late int _fontSize = _song.fontSize;
  late int _scrollSpeed = _song.scrollSpeed;
  Future<void> _persistChain = Future.value();

  late final Ticker _ticker;
  final _scrollCtrl = ScrollController();
  bool _autoScroll = false;
  bool _pausedByDrag = false;
  final _pos = ValueNotifier<double>(0);
  Duration _lastElapsed = Duration.zero;
  int _countdown = 0;
  late ({String text, List<double> tops, double totalHeight}) _layout;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _refreshLayout();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollCtrl.dispose();
    _pos.dispose();
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
      totalHeight: '\n'.allMatches(rendered.text).length * lineHeight,
    );
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
        _scrollSpeed = updated.scrollSpeed;
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
    _persist(v, _fontSize, _scrollSpeed);
  }

  void _setFontSize(int value) {
    final v = value.clamp(10, 28);
    if (v == _fontSize) return;
    setState(() {
      _fontSize = v;
      _refreshLayout();
    });
    _persist(_semitones, v, _scrollSpeed);
  }

  void _setScrollSpeed(int value) {
    final v = value.clamp(1, 60);
    if (v == _scrollSpeed) return;
    setState(() => _scrollSpeed = v);
    _persist(_semitones, _fontSize, v);
  }

  void _persist(int semitones, int fontSize, int scrollSpeed) {
    // Быстрые нажатия не должны гоняться за файловой записью.
    _persistChain = _persistChain.then((_) async {
      try {
        final name = await _storage.writeSong(
          desiredTitle: _song.title,
          content: Song.withHeaders(
            fontSize: fontSize,
            scrollSpeed: scrollSpeed,
            body: renderSong(parseSong(_song.content).transposed(semitones)),
          ),
          oldFileName: _song.fileName,
        );
        _song = _song.copyWith(
          fileName: name,
          transpose: 0,
          fontSize: fontSize,
          scrollSpeed: scrollSpeed,
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

  double _lineYAt(double pos) {
    final tops = _layout.tops;
    if (tops.isEmpty) return 0;
    if (pos <= 0) return tops.first;
    final last = tops.length - 1;
    if (pos >= last) {
      return tops[last] + (pos - last) * (_layout.totalHeight - tops[last]);
    }
    final k = pos.floor();
    final frac = pos - k;
    return tops[k] + (tops[k + 1] - tops[k]) * frac;
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

  void _syncPosFromScroll() {
    if (!_scrollCtrl.hasClients) return;
    final o = _scrollCtrl.offset;
    if (o <= 0) {
      _pos.value = 0;
      return;
    }
    _pos.value =
        _posForY(o + _scrollCtrl.position.viewportDimension * 0.4 - 16);
  }

  void _onTick(Duration elapsed) {
    if (!_scrollCtrl.hasClients) return;
    final tops = _layout.tops;
    if (tops.isEmpty) {
      _stopAutoScroll();
      return;
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _pos.value += dt * _scrollSpeed / 60;
    if (_pos.value >= tops.length) {
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      _stopAutoScroll();
      return;
    }
    final max = _scrollCtrl.position.maxScrollExtent;
    final target = targetOffset(
      lineTop: _lineYAt(_pos.value),
      viewport: _scrollCtrl.position.viewportDimension,
    );
    _scrollCtrl.jumpTo(target > max ? max : target);
  }

  Future<void> _startAutoScroll() async {
    setState(() {
      _autoScroll = true;
      _pausedByDrag = false;
      _countdown = 3;
      _syncPosFromScroll();
    });
    while (_countdown > 0 && mounted && _autoScroll) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_autoScroll) return;
      setState(() => _countdown = _countdown - 1);
    }
    if (!mounted || !_autoScroll) return;
    _syncPosFromScroll();
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  void _pauseAutoScroll() {
    if (_pausedByDrag) return;
    _pausedByDrag = true;
    _ticker.stop();
  }

  void _resumeAutoScroll() {
    if (!_pausedByDrag || !mounted || !_autoScroll) return;
    _pausedByDrag = false;
    _syncPosFromScroll();
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  void _stopAutoScroll() {
    _ticker.stop();
    _pausedByDrag = false;
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
            IconButton(
              tooltip: 'Медленнее',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove),
              onPressed: () => _setScrollSpeed(_scrollSpeed - 1),
            ),
            Text(
              '$_scrollSpeed строк/мин',
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Быстрее',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: () => _setScrollSpeed(_scrollSpeed + 1),
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
            decoration: BoxDecoration(
              border: Border.all(
                color: _fontSize == defaultFontSize
                    ? Theme.of(context).dividerColor
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$_fontSize',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
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
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification &&
                        n.dragDetails != null &&
                        _autoScroll) {
                      if (_ticker.isActive) {
                        _pauseAutoScroll();
                      } else {
                        _stopAutoScroll();
                      }
                    } else if (n is ScrollEndNotification && _pausedByDrag) {
                      _resumeAutoScroll();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(32, 16, 16, 32),
                    child: SelectableText(text, style: mono),
                  ),
                ),
                if (_autoScroll)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_scrollCtrl, _pos]),
                        builder: (_, _) {
                          if (!_scrollCtrl.hasClients) {
                            return const SizedBox.shrink();
                          }
                          final screenY =
                              _lineYAt(_pos.value) + 16 - _scrollCtrl.offset;
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
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                      ),
                      child: Text(
                        '$_countdown',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
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
