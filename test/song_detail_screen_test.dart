import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_book/models/song.dart';
import 'package:song_book/screens/song_detail_screen.dart';

void main() {
  testWidgets('автоскролл не выходит за maxScrollExtent', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = List.generate(60, (i) => 'строка $i').join('\n');
    final song = Song(
      fileName: 'test.txt',
      title: 'Тест',
      content: content,
      fontSize: 20,
      scrollSpeed: 60,
    );

    await tester.pumpWidget(MaterialApp(home: SongDetailScreen(song: song)));
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(seconds: 1));
      final max = position.maxScrollExtent;
      expect(
        position.pixels,
        lessThanOrEqualTo(max + 0.001),
        reason: 'тик $i: offset ушёл за maxScrollExtent',
      );
    }

    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('ручной скролл ставит автоскролл на паузу и возобновляет', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final content = List.generate(60, (i) => 'строка $i').join('\n');
    final song = Song(
      fileName: 'test.txt',
      title: 'Тест',
      content: content,
      fontSize: 20,
      scrollSpeed: 60,
    );

    await tester.pumpWidget(MaterialApp(home: SongDetailScreen(song: song)));
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    for (var i = 0; i < 30 && position.pixels <= 0; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(position.pixels, greaterThan(0));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pump();

    final afterDrag = position.pixels;
    expect(find.byTooltip('Пауза'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(position.pixels, greaterThan(afterDrag + 0.5));
  });
}
