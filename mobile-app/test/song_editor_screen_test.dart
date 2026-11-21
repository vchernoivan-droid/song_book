import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:song_book/models/song.dart';
import 'package:song_book/screens/song_editor_screen.dart';
import 'package:song_book/services/song_storage.dart';
import 'package:song_book/services/tag_store.dart';

class _FakeStorage implements SongStorage {
  const _FakeStorage();

  @override
  Future<List<Song>> listSongs() async => [];

  @override
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  }) async =>
      'New.txt';

  @override
  Future<void> deleteSong(String fileName) async {}

  @override
  Future<void> seedIfFirstRun() async {}
}

class _EditorPage {
  final WidgetTester _tester;
  final SongStorage storage;
  final TagStore tagStore;
  final Song? song;

  _EditorPage(
    this._tester, {
    required this.storage,
    required this.tagStore,
    this.song,
  });

  Future<void> open() async {
    await _tester.pumpWidget(MaterialApp(
      home: SongEditorScreen(
        song: song,
        storage: storage,
        tagStore: tagStore,
      ),
    ));
    await _tester.pumpAndSettle();
  }

  Future<void> save(String title) async {
    await _tester.enterText(find.byType(TextField).first, title);
    await _tester.tap(find.byTooltip('Сохранить'));
    await _tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('переименование песни переносит тэги', (tester) async {
    final store = await TagStore.seeded({
      'Old.txt': ['Дом'],
    });
    final page = _EditorPage(
      tester,
      storage: const _FakeStorage(),
      tagStore: store,
      song: const Song(fileName: 'Old.txt', title: 'Старое', content: 'текст'),
    );

    await page.open();
    await page.save('Новое');

    expect(await store.all(), {
      'New.txt': ['Дом'],
    });
  });
}
