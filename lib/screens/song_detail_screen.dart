import 'package:flutter/material.dart';

import '../models/song.dart';
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

class _SongDetailScreenState extends State<SongDetailScreen> {
  final _storage = SongStorage();
  late Song _song = widget.song;
  late int _semitones = _song.transpose;
  bool _pretty = true;
  Future<void> _persistChain = Future.value();

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
      });
    }
  }

  void _shiftTo(int value) {
    final v = value.clamp(-11, 11);
    if (v == _semitones) return;
    setState(() => _semitones = v);

    // Быстрые нажатия не должны гоняться за файловой записью.
    _persistChain = _persistChain.then((_) async {
      final body = _song.content;
      try {
        final name = await _storage.writeSong(
          desiredTitle: _song.title,
          content: Song.withTransposeHeader(v, body),
          oldFileName: _song.fileName,
        );
        _song = _song.copyWith(fileName: name, transpose: v);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить транспонирование')),
          );
        }
      }
    });
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

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'Roboto Mono', fontSize: 15, height: 1.35);
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
            tooltip: 'На полтона ниже',
            icon: const Icon(Icons.remove),
            onPressed: () => _shiftTo(_semitones - 1),
          ),
          Tooltip(
            message: 'Сбросить транспонирование',
            child: GestureDetector(
              onTap: () => _shiftTo(0),
              child: Container(
                width: 44,
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
            ),
          ),
          IconButton(
            tooltip: 'На полтона выше',
            icon: const Icon(Icons.add),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: SelectableText(displayed, style: mono),
      ),
    );
  }
}
