import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/song.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'drift_tag_store.dart';
import 'song_storage.dart';

class DriftSongStorage implements SongStorage {
  final AppDatabase db;
  final Directory? documentsDir;

  DriftSongStorage(this.db, {this.documentsDir});

  @override
  Future<List<Song>> listSongs() async {
    final rows = await db.select(db.songRows).get();
    final songs = [
      for (final row in rows)
        Song(
          fileName: row.id,
          title: row.title,
          content: row.content,
          transpose: row.transpose,
        ),
    ];
    songs.sort((a, b) {
      final la = a.title.toLowerCase();
      final lb = b.title.toLowerCase();
      return la == lb ? a.title.compareTo(b.title) : la.compareTo(lb);
    });
    return songs;
  }

  static const _uuid = Uuid();

  @override
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  }) async {
    if (oldFileName == null) {
      final id = _uuid.v4();
      await db.into(db.songRows).insert(SongRowsCompanion.insert(
            id: id,
            title: desiredTitle,
            content: content,
            updatedAt: DateTime.now(),
          ));
      return id;
    }
    await (db.update(db.songRows)..where((r) => r.id.equals(oldFileName)))
        .write(SongRowsCompanion(
      title: Value(desiredTitle),
      content: Value(content),
      updatedAt: Value(DateTime.now()),
    ));
    return oldFileName;
  }

  @override
  Future<void> deleteSong(String fileName) async {
    await (db.delete(db.songRows)..where((r) => r.id.equals(fileName))).go();
  }

  @override
  Future<void> seedIfFirstRun() async {
    final base = documentsDir ?? await getApplicationDocumentsDirectory();
    final songsDir = Directory(p.join(base.path, 'songs'));
    if (!songsDir.existsSync()) return;
    final files = songsDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.txt'))
        .toList();
    if (files.isEmpty) return;

    final imported = <String, String>{};
    for (final f in files) {
      final String raw;
      try {
        raw = f.readAsStringSync();
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
      final name = p.basename(f.path);
      final title = name.endsWith('.txt')
          ? name.substring(0, name.length - 4)
          : name;
      final song = Song.fromRaw(
        fileName: name,
        title: title,
        rawContent: raw,
      );
      final id = _uuid.v4();
      await db.into(db.songRows).insert(SongRowsCompanion.insert(
            id: id,
            title: song.title,
            content: song.content,
            transpose: Value(song.transpose),
            updatedAt: DateTime.now(),
          ));
      imported[name] = id;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawTags = prefs.getString('tags_data');
    if (rawTags != null) {
      final decoded = jsonDecode(rawTags);
      if (decoded is Map) {
        final tagStore = DriftTagStore(db);
        for (final entry in decoded.entries) {
          final songId = imported[entry.key.toString()];
          if (songId == null) continue;
          await tagStore.setTags(
            songId,
            [for (final t in entry.value as List) t.toString()],
          );
        }
      }
    }

    await songsDir.rename(p.join(base.path, 'songs.imported'));
  }
}
