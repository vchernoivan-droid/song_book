import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/tables.dart';

class DriftTagStore {
  final AppDatabase db;

  DriftTagStore(this.db);

  static const _uuid = Uuid();

  Future<Map<String, List<String>>> all() async {
    final rows = await (db.select(db.playlistSongRows).join([
      innerJoin(db.playlistRows, db.playlistRows.id
          .equalsExp(db.playlistSongRows.playlistId)),
    ])).get();

    final result = <String, List<String>>{};
    for (final row in rows) {
      final songId = row.readTable(db.playlistSongRows).songId;
      final tag = row.readTable(db.playlistRows).name;
      (result[songId] ??= []).add(tag);
    }
    return result;
  }

  static int _byTagLower(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    return la == lb ? a.compareTo(b) : la.compareTo(lb);
  }

  Future<List<String>> allTags() async {
    final names = await db.select(db.playlistRows).get();
    return [for (final p in names) p.name]..sort(_byTagLower);
  }

  Future<List<String>> tagsOf(String fileName) async {
    final query = db.select(db.playlistSongRows).join([
      innerJoin(db.playlistRows,
          db.playlistRows.id.equalsExp(db.playlistSongRows.playlistId)),
    ])
      ..where(db.playlistSongRows.songId.equals(fileName));
    final rows = await query.get();
    return [for (final row in rows) row.readTable(db.playlistRows).name]
      ..sort(_byTagLower);
  }

  Future<void> deleteSong(String fileName) async {
    await (db.delete(db.playlistSongRows)
          ..where((l) => l.songId.equals(fileName)))
        .go();
    final usedIds =
        (await db.select(db.playlistSongRows).get()).map((l) => l.playlistId).toSet();
    for (final p in await db.select(db.playlistRows).get()) {
      if (!usedIds.contains(p.id)) {
        await (db.delete(db.playlistRows)..where((r) => r.id.equals(p.id))).go();
      }
    }
  }

  Future<void> deleteTag(String name) async {
    final playlist = await (db.select(db.playlistRows)
          ..where((p) => p.name.equals(name)))
        .getSingleOrNull();
    if (playlist == null) return;
    await (db.delete(db.playlistSongRows)
          ..where((l) => l.playlistId.equals(playlist.id)))
        .go();
    await (db.delete(db.playlistRows)..where((p) => p.id.equals(playlist.id)))
        .go();
  }

  Future<void> renameTag(String oldName, String newName) async {
    final existing = await (db.select(db.playlistRows)
          ..where((p) => p.name.equals(newName)))
        .getSingleOrNull();
    final source = await (db.select(db.playlistRows)
          ..where((p) => p.name.equals(oldName)))
        .getSingleOrNull();
    if (source == null) return;

    if (existing != null) {
      final sourceLinks =
          await (db.select(db.playlistSongRows)
                ..where((l) => l.playlistId.equals(source.id)))
              .get();
      for (final link in sourceLinks) {
        final duplicate = await (db.select(db.playlistSongRows)
              ..where((l) => (l.playlistId.equals(existing.id) & l.songId.equals(link.songId))))
            .getSingleOrNull();
        if (duplicate != null) {
          await (db.delete(db.playlistSongRows)
                ..where((l) => (l.playlistId.equals(source.id) & l.songId.equals(link.songId))))
              .go();
        } else {
          await (db.update(db.playlistSongRows)
                ..where((l) => (l.playlistId.equals(source.id) & l.songId.equals(link.songId))))
              .write(PlaylistSongRowsCompanion(playlistId: Value(existing.id)));
        }
      }
      await (db.delete(db.playlistRows)..where((p) => p.id.equals(source.id)))
          .go();
    } else {
      await (db.update(db.playlistRows)..where((p) => p.name.equals(oldName)))
          .write(PlaylistRowsCompanion(name: Value(newName)));
    }
  }

  Future<void> setTags(String fileName, List<String> tags) async {
    final ids = <String>[];
    for (final tag in tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()) {
      final existing = await (db.select(db.playlistRows)
            ..where((p) => p.name.equals(tag)))
          .getSingleOrNull();
      ids.add(existing?.id ?? await _createPlaylist(tag));
    }

    await (db.delete(db.playlistSongRows)
          ..where((l) => l.songId.equals(fileName)))
        .go();

    for (final playlistId in ids) {
      await db.into(db.playlistSongRows).insert(PlaylistSongRowsCompanion.insert(
            playlistId: playlistId,
            songId: fileName,
            updatedAt: DateTime.now(),
          ));
    }

    if (ids.isEmpty) {
      final linked = await db.select(db.playlistSongRows).get();
      final usedIds = linked.map((l) => l.playlistId).toSet();
      for (final p in await db.select(db.playlistRows).get()) {
        if (!usedIds.contains(p.id)) {
          await (db.delete(db.playlistRows)..where((r) => r.id.equals(p.id))).go();
        }
      }
    }
  }

  Future<String> _createPlaylist(String name) async {
    final id = _uuid.v4();
    await db.into(db.playlistRows).insert(PlaylistRowsCompanion.insert(
          id: id,
          name: name,
          updatedAt: DateTime.now(),
        ));
    return id;
  }
}
