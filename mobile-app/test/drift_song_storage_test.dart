import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_book/db/database.dart';
import 'package:song_book/db/tables.dart';
import 'package:song_book/services/drift_song_storage.dart';

Future<void> seedSong(
  AppDatabase db, {
  required String id,
  required String title,
  required String content,
  int transpose = 0,
}) async {
  await db.into(db.songRows).insert(SongRowsCompanion.insert(
        id: id,
        title: title,
        content: content,
        transpose: Value(transpose),
        updatedAt: DateTime.now(),
      ));
}

void main() {
  late AppDatabase db;
  late DriftSongStorage storage;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    storage = DriftSongStorage(db);
  });

  tearDown(() => db.close());

  test('deleteSong удаляет строку песни', () async {
    await seedSong(db, id: 'guid-1', title: 'Тест', content: 'т');

    await storage.deleteSong('guid-1');

    expect(await db.select(db.songRows).get(), isEmpty);
  });

  test('writeSong с oldFileName обновляет песню, гуид прежний', () async {
    await seedSong(db, id: 'guid-1', title: 'Старая', content: 'старый текст');

    final id = await storage.writeSong(
      desiredTitle: 'Новая',
      content: 'новый текст',
      oldFileName: 'guid-1',
    );

    final row = await db.select(db.songRows).getSingle();
    expect(id, 'guid-1');
    expect(row.title, 'Новая');
    expect(row.content, 'новый текст');
  });

  test('writeSong создаёт песню с новым гуидом', () async {
    final id = await storage.writeSong(desiredTitle: 'Новая', content: 'текст');

    final row = await db.select(db.songRows).getSingle();
    expect(row, isNotNull);
    expect(row.id, id);
  });

  test('listSongs сортирует по названию без учёта регистра', () async {
    await seedSong(db, id: 'a', title: 'Ялта', content: 'т');
    await seedSong(db, id: 'b', title: 'анапа', content: 'т');

    final songs = await storage.listSongs();

    expect(songs.map((s) => s.title), ['анапа', 'Ялта']);
  });

  test('seedIfFirstRun переносит тэги из prefs в плейлисты', () async {
    SharedPreferences.setMockInitialValues({
      'tags_data': jsonEncode({
        'test.txt': ['Дом'],
      }),
    });
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final songsDir = await Directory(p.join(dir.path, 'songs')).create(recursive: true);
    await File(p.join(songsDir.path, 'test.txt')).writeAsString('текст');
    storage = DriftSongStorage(db, documentsDir: dir);

    await storage.seedIfFirstRun();

    final row = await db.select(db.songRows).getSingle();
    final link = await db.select(db.playlistSongRows).getSingle();
    expect(link.songId, row.id);
    final playlist = await (db.select(db.playlistRows)
          ..where((p) => p.id.equals(link.playlistId)))
        .getSingle();
    expect(playlist.name, 'Дом');
  });

  test('seedIfFirstRun: битый файл пропускается, остальные импортируются', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final songsDir = await Directory(p.join(dir.path, 'songs')).create(recursive: true);
    await File(p.join(songsDir.path, 'good.txt')).writeAsString('текст');
    await File(p.join(songsDir.path, 'broken.txt'))
        .writeAsBytes([0xff, 0xfe, 0x00, 0xd8]);
    storage = DriftSongStorage(db, documentsDir: dir);

    await storage.seedIfFirstRun();

    final row = await db.select(db.songRows).getSingle();
    expect(row.title, 'good');
  });

  test('seedIfFirstRun: каталог уезжает в songs.imported, повтор без дублей', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final songsDir = await Directory(p.join(dir.path, 'songs')).create(recursive: true);
    await File(p.join(songsDir.path, 'test.txt')).writeAsString('текст');
    storage = DriftSongStorage(db, documentsDir: dir);

    await storage.seedIfFirstRun();
    await storage.seedIfFirstRun();

    expect(await db.select(db.songRows).get(), hasLength(1));
    expect(Directory(p.join(dir.path, 'songs')).existsSync(), isFalse);
    expect(Directory(p.join(dir.path, 'songs.imported')).existsSync(), isTrue);
  });

  test('seedIfFirstRun импортирует файл: transpose в колонку, тело без шапки', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final songsDir = await Directory(p.join(dir.path, 'songs')).create(recursive: true);
    await File(p.join(songsDir.path, 'test.txt'))
        .writeAsString('# transpose: 2\nтекст песни');
    storage = DriftSongStorage(db, documentsDir: dir);

    await storage.seedIfFirstRun();

    final row = await db.select(db.songRows).getSingle();
    expect(row.title, 'test');
    expect(row.transpose, 2);
    expect(row.content, 'текст песни');
  });

  test('listSongs читает песни из БД', () async {
    await seedSong(db,
        id: 'guid-1', title: 'Тест', content: 'текст', transpose: 3);

    final songs = await storage.listSongs();

    expect(songs, hasLength(1));
    expect(songs.single.fileName, 'guid-1');
    expect(songs.single.title, 'Тест');
    expect(songs.single.content, 'текст');
    expect(songs.single.transpose, 3);
  });
}
