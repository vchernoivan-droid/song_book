import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:song_book/services/tag_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setTags обрезает пробелы вокруг тэга', () async {
    final store = TagStore();

    await store.setTags('a.txt', [' Кемпинг ']);

    expect(await store.all(), {
      'a.txt': ['Кемпинг'],
    });
  });

  test('setTags не сохраняет пустые имена', () async {
    final store = TagStore();

    await store.setTags('a.txt', ['Дом', '']);

    expect(await store.all(), {
      'a.txt': ['Дом'],
    });
  });

  test('setTags схлопывает точные дубликаты', () async {
    final store = TagStore();

    await store.setTags('a.txt', ['Дом', 'Дом']);

    expect(await store.all(), {
      'a.txt': ['Дом'],
    });
  });

  test('setTags сортирует без учёта регистра', () async {
    final store = TagStore();

    await store.setTags('a.txt', ['Ялта', 'анапа']);

    expect(await store.all(), {
      'a.txt': ['анапа', 'Ялта'],
    });
  });

  test('setTags пустым списком удаляет запись', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });

    await store.setTags('a.txt', []);

    expect(await store.all(), {});
  });

  test('allTags объединяет тэги всех песен', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Кемпинг'],
    });

    expect(await store.allTags(), containsAll(['Дом', 'Кемпинг']));
  });

  test('allTags сортирует без учёта регистра', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Ялта'],
      'b.txt': ['анапа'],
    });

    expect(await store.allTags(), ['анапа', 'Ялта']);
  });

  test('пустое хранилище — allTags пустой', () async {
    final store = TagStore();

    expect(await store.allTags(), []);
  });

  test('setTags сохраняет тэги песни, all читает карту', () async {
    final store = TagStore();

    await store.setTags('Hotel_California.txt', ['Дом', 'Кемпинг']);

    expect(await store.all(), {
      'Hotel_California.txt': ['Дом', 'Кемпинг'],
    });
  });

  test('tagsOf возвращает тэги песни', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });

    expect(await store.tagsOf('a.txt'), ['Дом']);
  });

  test('tagsOf отсутствующего файла — пустой список', () async {
    final store = TagStore();

    expect(await store.tagsOf('нет.txt'), []);
  });

  test('renameTag обновляет тэг у всех песен', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Дом'],
    });

    await store.renameTag('Дом', 'Дача');

    expect(await store.all(), {
      'a.txt': ['Дача'],
      'b.txt': ['Дача'],
    });
  });

  test('renameTag сохраняет остальные тэги песни', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом', 'Кемпинг'],
    });

    await store.renameTag('Дом', 'Ялта');

    expect(await store.tagsOf('a.txt'), containsAll(['Кемпинг', 'Ялта']));
  });

  test('renameTag при коллизии имён мержит в один', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом', 'дом'],
    });

    await store.renameTag('дом', 'Дом');

    expect(await store.all(), {
      'a.txt': ['Дом'],
    });
  });

  test('deleteTag снимает тэг с песни', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом', 'Кемпинг'],
    });

    await store.deleteTag('Дом');

    expect(await store.all(), {
      'a.txt': ['Кемпинг'],
    });
  });

  test('deleteTag удаляет опустевшую запись', () async {
    final store = await TagStore.seeded({
      'b.txt': ['Дом'],
    });

    await store.deleteTag('Дом');

    expect(await store.all(), {});
  });

  test('deleteSong удаляет запись песни', () async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });

    await store.deleteSong('a.txt');

    expect(await store.all(), {});
  });
}
