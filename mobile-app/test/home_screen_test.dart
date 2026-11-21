import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:song_book/models/song.dart';
import 'package:song_book/screens/home_screen.dart';
import 'package:song_book/screens/song_detail_screen.dart';
import 'package:song_book/services/song_storage.dart';
import 'package:song_book/services/tag_store.dart';

class _FakeStorage implements SongStorage {
  _FakeStorage(this.songs);

  final List<Song> songs;

  @override
  Future<List<Song>> listSongs() async => songs;

  @override
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  }) async =>
      desiredTitle;

  @override
  Future<void> deleteSong(String fileName) async {}

  @override
  Future<void> seedIfFirstRun() async {}
}

class _HomePage {
  final WidgetTester _tester;
  final SongStorage storage;
  final TagStore tagStore;

  _HomePage(
    this._tester, {
    required this.storage,
    required this.tagStore,
  });

  Future<void> open() async {
    await _tester.pumpWidget(MaterialApp(
      home: HomeScreen(storage: storage, tagStore: tagStore),
    ));
    await _tester.pumpAndSettle();
  }

  Future<void> tapTag(String name) async {
    await _tester.tap(find.text(name));
    await _tester.pumpAndSettle();
  }

  Future<void> openSong(String title) async {
    await _tester.tap(find.text(title));
    await _tester.pumpAndSettle();
  }

  Future<void> back() async {
    await _tester.pageBack();
    await _tester.pumpAndSettle();
  }

  Future<void> deleteSong(String title) async {
    await _tester.drag(find.text(title), const Offset(-500, 0));
    await _tester.pumpAndSettle();
    await _tester.tap(find.text('Удалить'));
    await _tester.pumpAndSettle();
  }

  Future<void> search(String query) async {
    await _tester.enterText(find.byType(TextField), query);
    await _tester.pumpAndSettle();
  }

  Future<void> clearActiveTag() async {
    await _tester.tap(find.byIcon(Icons.close));
    await _tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('тап по чипу фильтрует список по тэгу', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Кемпинг'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'текст'),
        const Song(fileName: 'b.txt', title: 'Вторая', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.tapTag('Дом');

    expect(find.byType(SongDetailScreen), findsNothing);
    expect(find.text('Первая'), findsOneWidget);
    expect(find.text('Вторая'), findsNothing);
  });

  testWidgets('активный тэг показан у поиска и снимается', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Кемпинг'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'текст'),
        const Song(fileName: 'b.txt', title: 'Вторая', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.tapTag('Дом');
    await page.clearActiveTag();

    expect(find.text('Первая'), findsOneWidget);
    expect(find.text('Вторая'), findsOneWidget);
  });

  testWidgets('фильтр по тэгу комбинируется с поиском', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'море'),
        const Song(fileName: 'b.txt', title: 'Вторая', content: 'море'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.tapTag('Дом');
    await page.search('мор');

    expect(find.text('Первая'), findsOneWidget);
    expect(find.text('Вторая'), findsNothing);
  });

  testWidgets('мёртвый тэг снимает фильтр', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'текст'),
        const Song(fileName: 'b.txt', title: 'Вторая', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.tapTag('Дом');
    await page.deleteSong('Первая');

    expect(find.text('Вторая'), findsOneWidget);
  });

  testWidgets('свайп-удаление песни вычищает тэги', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.deleteSong('Первая');

    expect(await store.all(), {});
  });

  testWidgets('мёртвый тэг снимает фильтр после возврата с экрана песни', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Первая', content: 'текст'),
        const Song(fileName: 'b.txt', title: 'Вторая', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();
    await page.tapTag('Дом');
    await page.openSong('Первая');
    await store.renameTag('Дом', 'Дача');
    await page.back();

    expect(find.text('Первая'), findsOneWidget);
    expect(find.text('Вторая'), findsOneWidget);
  });

  testWidgets('чипы тэгов видны на строках', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
    });
    final page = _HomePage(
      tester,
      storage: _FakeStorage([
        const Song(fileName: 'a.txt', title: 'Песня', content: 'текст'),
      ]),
      tagStore: store,
    );

    await page.open();

    expect(find.text('Дом'), findsOneWidget);
  });
}
