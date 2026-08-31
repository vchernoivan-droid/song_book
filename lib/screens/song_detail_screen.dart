import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/song.dart';
import '../services/auto_scroll.dart';
import '../services/chord_transposer.dart';
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
  late int _semitones = _song.transpose;
  late int _fontSize = _song.fontSize;
  late int _scrollSpeed = _song.scrollSpeed;
  bool _pretty = true;
  Future<void> _persistChain = Future.value();

  late final Ticker _ticker;
  final _scrollCtrl = ScrollController();
  bool _autoScroll = false;
  double _scrollPxPerSec = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Текст, который видит пользователь: исходный или канонический (из модели).
  String get _displayedBody {
    final transposed = transposeSongContent(_song.content, _semitones);
    if (!_pretty) return transposed;
    return renderSong(parseSong(transposed), fromSource: false);
  }

  Future<void> _edit() async {
    // Редактор открываем ровно с тем текстом, что на экране: сохранится
    // он как есть, шапка транспонирования не пишется (transpose = 0).
    final editing = _song.copyWith(content: _displayedBody, transpose: 0);
    final updated = await Navigator.of(context).push<Song?>(
      MaterialPageRoute(builder: (_) => SongEditorScreen(song: editing)),
    );
    if (updated != null && mounted) {
      setState(() {
        _song = updated;
        _semitones = updated.transpose;
        _fontSize = updated.fontSize;
        _scrollSpeed = updated.scrollSpeed;
      });
    }
  }

  void _shiftTo(int value) {
    final v = value.clamp(-11, 11);
    if (v == _semitones) return;
    setState(() => _semitones = v);
    _persist(v, _fontSize, _scrollSpeed);
  }

  void _setFontSize(int value) {
    final v = value.clamp(10, 28);
    if (v == _fontSize) return;
    setState(() => _fontSize = v);
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
            transpose: semitones,
            fontSize: fontSize,
            scrollSpeed: scrollSpeed,
            body: _song.content,
          ),
          oldFileName: _song.fileName,
        );
        _song = _song.copyWith(
          fileName: name,
          transpose: semitones,
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

  double _scrollPxPerSecond() {
    final lineHeight = _fontSize * 1.35;
    final transposed = transposeSongContent(_song.content, _semitones);
    final parsed = parseSong(transposed);
    final body = _pretty ? renderSong(parsed, fromSource: false) : transposed;

    final parts = body.split('\n');
    var physical = parts.length;
    if (parts.isNotEmpty && parts.last.isEmpty) physical--;

    var tokenLines = physical;
    if (_pretty) {
      tokenLines =
          parsed.sections.fold(0, (sum, s) => sum + s.lines.length);
    }
    return autoScrollPxPerSecond(
      linesPerMinute: _scrollSpeed,
      tokenLines: tokenLines,
      physicalLines: physical,
      lineHeight: lineHeight,
    );
  }

  void _onTick(Duration elapsed) {
    if (!_scrollCtrl.hasClients) return;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final max = _scrollCtrl.position.maxScrollExtent;
    final next = _scrollCtrl.offset + _scrollPxPerSec * dt;
    if (next >= max) {
      _scrollCtrl.jumpTo(max);
      _stopAutoScroll();
      return;
    }
    _scrollCtrl.jumpTo(next);
  }

  Future<void> _startAutoScroll() async {
    setState(() {
      _autoScroll = true;
      _scrollPxPerSec = _scrollPxPerSecond();
    });
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted || !_autoScroll) return;
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  void _stopAutoScroll() {
    _ticker.stop();
    if (mounted) setState(() => _autoScroll = false);
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

  String get _semitonesLabel {
    final v = _semitones;
    return v == 0 ? '0' : v > 0 ? '+$v' : '$v';
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
                    final value =
                        max <= 0 ? 0.0 : (pos.pixels / max).clamp(0.0, 1.0);
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
        fontFamily: 'Roboto Mono', fontSize: _fontSize.toDouble(), height: 1.35);
    final displayed = _song.content.isEmpty ? '(пусто)' : _displayedBody;
    return Scaffold(
      appBar: AppBar(
        title: Text(_song.title, overflow: TextOverflow.ellipsis),
        actions: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Исходник')),
              ButtonSegment(value: true, label: Text('Красиво')),
            ],
            selected: {_pretty},
            onSelectionChanged: (selection) =>
                setState(() => _pretty = selection.first),
          ),
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
                color: _fontSize == 15
                    ? Theme.of(context).dividerColor
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$_fontSize',
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
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
          Container(
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: _semitones == 0
                    ? Theme.of(context).dividerColor
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _semitonesLabel,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
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
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: SelectableText(displayed, style: mono),
            ),
          ),
          _buildAutoScrollBar(),
        ],
      ),
    );
  }
}
