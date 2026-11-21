import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:song_book/services/tag_store.dart';
import 'package:song_book/widgets/manage_tags_dialog.dart';

class _ManageTagsPage {
  final WidgetTester _tester;
  final TagStore tagStore;
  final String songFileName;

  _ManageTagsPage(this._tester, {
    required this.tagStore,
    required this.songFileName,
  });

  Future<void> open() async {
    await _tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManageTagsDialog(tagStore: tagStore, songFileName: songFileName),
      ),
    ));
    await _tester.pumpAndSettle();
  }

  Future<void> checkTag(String name) async {
    await _tester.tap(find.text(name));
    await _tester.pumpAndSettle();
  }

  Future<void> addTag(String name) async {
    await _tester.enterText(find.byType(TextField), name);
    await _tester.tap(find.text('Добавить'));
    await _tester.pumpAndSettle();
  }

  Future<void> longPressTag(String name) async {
    await _tester.longPress(find.text(name));
    await _tester.pumpAndSettle();
  }

  Future<void> renameTag(String from, String to) async {
    await longPressTag(from);
    await _tester.tap(find.text('Переименовать'));
    await _tester.pumpAndSettle();
    await _tester.enterText(find.byType(TextField).last, to);
    await _tester.tap(find.text('Сохранить'));
    await _tester.pumpAndSettle();
  }

  Future<void> deleteTag(String name) async {
    await longPressTag(name);
    await _tester.tap(find.text('Удалить'));
    await _tester.pumpAndSettle();
  }

  Future<void> rightClickTag(String name) async {
    await _tester.tapAt(
      _tester.getCenter(find.text(name)),
      buttons: kSecondaryButton,
    );
    await _tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('длинный тап по тэгу открывает меню', (tester) async {
    final store = await TagStore.seeded({
      'b.txt': ['Кемпинг'],
    });
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.longPressTag('Кемпинг');

    expect(find.text('Переименовать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('новый тэг добавляется и вешается песне', (tester) async {
    final store = await TagStore.seeded({});
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.addTag('Дача');

    expect(await store.tagsOf('a.txt'), ['Дача']);
  });

  testWidgets('правый клик открывает меню', (tester) async {
    final store = await TagStore.seeded({
      'b.txt': ['Кемпинг'],
    });
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.rightClickTag('Кемпинг');

    expect(find.text('Переименовать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('переименование тэга обновляет все песни', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Дом'],
    });
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.renameTag('Дом', 'Дача');

    expect(await store.all(), {
      'a.txt': ['Дача'],
      'b.txt': ['Дача'],
    });
  });

  testWidgets('удаление тэга снимает его со всех песен', (tester) async {
    final store = await TagStore.seeded({
      'a.txt': ['Дом'],
      'b.txt': ['Дом'],
    });
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.deleteTag('Дом');

    expect(await store.all(), {});
  });

  testWidgets('чекбокс переключает тэг песни', (tester) async {
    final store = await TagStore.seeded({
      'b.txt': ['Кемпинг'],
    });
    final page = _ManageTagsPage(
      tester,
      tagStore: store,
      songFileName: 'a.txt',
    );

    await page.open();
    await page.checkTag('Кемпинг');

    expect(await store.tagsOf('a.txt'), ['Кемпинг']);
  });
}
