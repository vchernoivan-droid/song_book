import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/chord_transposer.dart';
import '../services/song_parser.dart';
import '../services/song_storage.dart';

/// Экран добавления / редактирования песни.
///
/// Если [song] == null — создаём новую, иначе редактируем существующую.
class SongEditorScreen extends StatefulWidget {
  final Song? song;

  /// Предзаполнение для новой песни (например, текст из интернета).
  /// Применяется только если [song] == null.
  final String? prefillTitle;
  final String? prefillContent;

  const SongEditorScreen({
    super.key,
    this.song,
    this.prefillTitle,
    this.prefillContent,
  });

  @override
  State<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends State<SongEditorScreen> {
  final _storage = SongStorage();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final String _origTitle;
  late final String _origContent;
  late final int _transpose = widget.song?.transpose ?? 0;
  late final int _fontSize = widget.song?.fontSize ?? 15;
  late final int _scrollSpeed = widget.song?.scrollSpeed ?? 15;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialTitle = widget.song?.title ?? widget.prefillTitle ?? '';
    final initialContent = widget.song?.content ?? widget.prefillContent ?? '';
    _origTitle = initialTitle;
    _origContent = initialContent;
    _titleCtrl = TextEditingController(text: initialTitle);
    _contentCtrl = TextEditingController(text: initialContent);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _titleCtrl.text != _origTitle || _contentCtrl.text != _origContent;

  Future<void> _replaceChord() async {
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заменить аккорд'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fromCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Найти аккорд',
                hintText: 'Am',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: toCtrl,
              decoration: const InputDecoration(
                labelText: 'Заменить на',
                hintText: 'Bm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Заменить'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final fromText = fromCtrl.text.trim();
    final toText = toCtrl.text.trim();
    fromCtrl.dispose();
    toCtrl.dispose();
    if (ok != true) return;

    final from = parseChord(fromText);
    final to = parseChord(toText);
    if (from == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректные аккорды')),
      );
      return;
    }

    final result = replaceChordContent(_contentCtrl.text, from, to);
    if (result.count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аккорд не найден')),
      );
      return;
    }

    setState(() => _contentCtrl.text = result.content);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Заменено аккордов: ${result.count}')),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название песни')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final body = renderSong(parseSong(_contentCtrl.text));
      final fileName = await _storage.writeSong(
        desiredTitle: title,
        content: Song.withHeaders(
          transpose: _transpose,
          fontSize: _fontSize,
          scrollSpeed: _scrollSpeed,
          body: body,
        ),
        oldFileName: widget.song?.fileName,
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        Song(
          fileName: fileName,
          title: title,
          content: body,
          transpose: _transpose,
          fontSize: _fontSize,
          scrollSpeed: _scrollSpeed,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Подтверждение перед закрытием без сохранения.
  Future<bool> _confirmExit() async {
    if (!_hasChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть без сохранения?'),
        content: const Text('Несохранённые изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.song == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmExit()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'Новая песня' : 'Редактировать'),
          actions: [
            IconButton(
              tooltip: 'Заменить аккорд',
              icon: const Icon(Icons.find_replace),
              onPressed: _replaceChord,
            ),
            IconButton(
              tooltip: 'Сохранить',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: isNew,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Например, Hotel California',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _contentCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'Roboto Mono', fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Текст песни / аккорды / табы',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
