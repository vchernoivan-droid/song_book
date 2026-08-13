import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'example_song.dart';
import 'song_storage.dart';

/// Файловое хранилище (мобайл/десктоп).
///
/// Каждая песня — отдельный файл `.txt` в подкаталоге `songs`
/// внутри documents-каталога приложения.
class FileSongStorage implements SongStorage {
  static const _dirName = 'songs';
  static const _ext = '.txt';

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, _dirName));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  String _titleFromName(String fileName) => fileName.endsWith(_ext)
      ? fileName.substring(0, fileName.length - _ext.length)
      : fileName;

  String _sanitize(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    if (s.isEmpty) s = 'Без названия';
    return s;
  }

  String _uniqueName(Directory dir, String baseName, String? exclude) {
    var name = '$baseName$_ext';
    var i = 2;
    while (name != exclude && File(p.join(dir.path, name)).existsSync()) {
      name = '$baseName ($i)$_ext';
      i++;
    }
    return name;
  }

  @override
  Future<List<Song>> listSongs() async {
    final dir = await _dir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith(_ext))
        .toList();

    files.sort((a, b) => p
        .basename(a.path)
        .toLowerCase()
        .compareTo(p.basename(b.path).toLowerCase()));

    final songs = <Song>[];
    for (final f in files) {
      final name = p.basename(f.path);
      songs.add(Song(
        fileName: name,
        title: _titleFromName(name),
        content: f.readAsStringSync(),
      ));
    }
    return songs;
  }

  @override
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  }) async {
    final dir = await _dir();
    final base = _sanitize(desiredTitle);
    final name = _uniqueName(dir, base, oldFileName);

    await File(p.join(dir.path, name)).writeAsString(content);

    if (oldFileName != null && oldFileName != name) {
      final old = File(p.join(dir.path, oldFileName));
      if (old.existsSync()) await old.delete();
    }
    return name;
  }

  @override
  Future<void> deleteSong(String fileName) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, fileName));
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> seedIfFirstRun() async {
    final dir = await _dir();
    final marker = File(p.join(dir.parent.path, '.seeded'));
    if (marker.existsSync()) return;

    final hasFiles = dir.listSync().whereType<File>().isNotEmpty;
    if (!hasFiles) {
      await writeSong(
        desiredTitle: kExampleSongTitle,
        content: kExampleSongContent,
      );
    }
    marker.createSync(recursive: true);
  }
}
