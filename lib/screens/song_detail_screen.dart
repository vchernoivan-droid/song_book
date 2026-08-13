import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/song_storage.dart';
import 'song_editor_screen.dart';

/// Экран просмотра текста песни (моноширинный шрифт).
class SongDetailScreen extends StatefulWidget {
  final Song song;
  const SongDetailScreen({super.key, required this.song});

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  final _storage = SongStorage();
  late Song _song = widget.song;

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Song?>(
      MaterialPageRoute(builder: (_) => SongEditorScreen(song: _song)),
    );
    if (updated != null && mounted) {
      setState(() => _song = updated);
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

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'Roboto Mono', fontSize: 15, height: 1.35);
    return Scaffold(
      appBar: AppBar(
        title: Text(_song.title, overflow: TextOverflow.ellipsis),
        actions: [
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
        child: SelectableText(
          _song.content.isEmpty ? '(пусто)' : _song.content,
          style: mono,
        ),
      ),
    );
  }
}
