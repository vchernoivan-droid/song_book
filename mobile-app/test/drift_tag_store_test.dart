import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/db/database.dart';
import 'package:song_book/db/tables.dart';
import 'package:song_book/services/drift_tag_store.dart';
import 'package:uuid/uuid.dart';

Future<void> seedTags(
  AppDatabase db,
  String songId,
  List<String> tags,
) async {
  for (final tag in tags) {
    final existing = await (db.select(db.playlistRows)
          ..where((p) => p.name.equals(tag)))
        .getSingleOrNull();
    final playlistId = existing?.id ?? const Uuid().v4();
    if (existing == null) {
      await db.into(db.playlistRows).insert(PlaylistRowsCompanion.insert(
            id: playlistId,
            name: tag,
            updatedAt: DateTime.now(),
          ));
    }
    await db.into(db.playlistSongRows).insert(PlaylistSongRowsCompanion.insert(
          playlistId: playlistId,
          songId: songId,
          updatedAt: DateTime.now(),
        ));
  }
}

void main() {
  late AppDatabase db;
  late DriftTagStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftTagStore(db);
  });

  tearDown(() => db.close());

  test('setTags сортирует без учёта регистра', () async {
    await store.setTags('guid-1', ['Ялта', 'анапа']);

    expect(await store.tagsOf('guid-1'), ['анапа', 'Ялта']);
  });

  test('setTags схлопывает точные дубликаты', () async {
    await store.setTags('guid-1', ['Дом', 'Дом']);

    expect(await store.tagsOf('guid-1'), ['Дом']);
  });

  test('setTags не сохраняет пустые имена', () async {
    await store.setTags('guid-1', ['Дом', '']);

    expect(await store.tagsOf('guid-1'), ['Дом']);
  });

  test('setTags обрезает пробелы вокруг тэга', () async {
    await store.setTags('guid-1', [' Кемпинг ']);

    expect(await store.tagsOf('guid-1'), ['Кемпинг']);
  });

  test('allTags сортирует без учёта регистра', () async {
    await seedTags(db, 'guid-1', ['Ялта']);
    await seedTags(db, 'guid-2', ['анапа']);

    expect(await store.allTags(), ['анапа', 'Ялта']);
  });

  test('allTags объединяет тэги всех песен', () async {
    await seedTags(db, 'guid-1', ['Дом']);
    await seedTags(db, 'guid-2', ['Кемпинг']);

    expect(await store.allTags(), ['Дом', 'Кемпинг']);
  });

  test('tagsOf возвращает тэги песни', () async {
    await seedTags(db, 'guid-1', ['Дом', 'Кемпинг']);

    expect(await store.tagsOf('guid-1'), ['Дом', 'Кемпинг']);
  });

  test('tagsOf отсутствующего файла — пустой список', () async {
    expect(await store.tagsOf('нет'), []);
  });

  test('deleteSong не задевает чужие плейлисты', () async {
    await seedTags(db, 'guid-1', ['Дом']);
    await seedTags(db, 'guid-2', ['Дом', 'Кемпинг']);

    await store.deleteSong('guid-1');

    expect(await store.all(), {
      'guid-2': ['Дом', 'Кемпинг'],
    });
  });

  test('deleteSong чистит связки и не оставляет сироту-плейлист', () async {
    await seedTags(db, 'guid-1', ['Дом']);

    await store.deleteSong('guid-1');

    expect(await store.all(), {});
    expect(await db.select(db.playlistRows).get(), isEmpty);
  });

  test('deleteTag удаляет плейлист при нескольких песнях', () async {
    await seedTags(db, 'guid-1', ['Дом']);
    await seedTags(db, 'guid-2', ['Дом']);

    await store.deleteTag('Дом');

    expect(await store.all(), {});
    expect(await db.select(db.playlistRows).get(), isEmpty);
  });

  test('deleteTag снимает тэг с песни', () async {
    await seedTags(db, 'guid-1', ['Дом', 'Кемпинг']);

    await store.deleteTag('Дом');

    expect(await store.tagsOf('guid-1'), ['Кемпинг']);
  });

  test('renameTag при коллизии имён мержит в один', () async {
    await seedTags(db, 'guid-1', ['Дом']);
    await seedTags(db, 'guid-1', ['дом']);

    await store.renameTag('дом', 'Дом');

    expect(await store.tagsOf('guid-1'), ['Дом']);
  });

  test('renameTag сохраняет остальные тэги песни', () async {
    await seedTags(db, 'guid-1', ['Дом', 'Кемпинг']);

    await store.renameTag('Дом', 'Дача');

    expect(await store.tagsOf('guid-1'), containsAll(['Кемпинг', 'Дача']));
  });

  test('renameTag обновляет тэг у всех песен', () async {
    await seedTags(db, 'guid-1', ['Дом']);
    await seedTags(db, 'guid-2', ['Дом']);

    await store.renameTag('Дом', 'Дача');

    expect(await store.tagsOf('guid-1'), ['Дача']);
    expect(await store.tagsOf('guid-2'), ['Дача']);
  });

  test('setTags пустым списком удаляет запись и не оставляет мусора', () async {
    await seedTags(db, 'guid-1', ['Дом']);

    await store.setTags('guid-1', []);

    expect(await store.all(), {});
    expect(await db.select(db.playlistRows).get(), isEmpty);
  });

  test('setTags сохраняет тэги песни, all читает карту', () async {
    await store.setTags('guid-1', ['Дом', 'Кемпинг']);

    expect(await store.all(), {
      'guid-1': ['Дом', 'Кемпинг'],
    });
  });
}
