import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_book/models/song.dart';
import 'package:song_book/screens/song_detail_screen.dart';
import 'package:song_book/services/song_listen_logger.dart';

Finder _cursorPaint() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_CursorPainter',
    );

double _cursorY(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_cursorPaint()).painter as dynamic).y as double;

Song _song(String content, {int scrollSpeed = 60}) => Song(
      fileName: 'test.txt',
      title: 'Тест',
      content: content,
      fontSize: 20,
      scrollSpeed: scrollSpeed,
    );

String _lines(int n) => List.generate(n, (i) => 'строка $i').join('\n');

SongListenLogger _nullListenLogger({
  required String title,
  required int scrollSpeed,
  required int fontSize,
  required double Function() position,
}) =>
    _NullListenLogger();

class _NullListenLogger extends SongListenLogger {
  _NullListenLogger()
      : super(
          title: 'тест',
          scrollSpeed: 0,
          fontSize: 0,
          position: () => 0,
        );

  @override
  Future<bool> start() async => true;

  @override
  Future<void> stop() async {}

  @override
  void note(String tag) {}
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final docs = Directory.systemTemp.createTempSync('songbook_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return docs.path;
      return null;
    });
  });

  testWidgets('автоскролл не выходит за maxScrollExtent', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_lines(60)), listenLoggerFactory: _nullListenLogger)),
    );
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

  testWidgets('ручной скролл ставит автоскролл на паузу и возобновляет',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_lines(60)), listenLoggerFactory: _nullListenLogger)),
    );
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

  testWidgets('автоскролл проходит три фазы и останавливается', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_lines(60)), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final max = position.maxScrollExtent;
    final f40 = position.viewportDimension * 0.4;

    final trace = <({double offset, double y})>[];
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byTooltip('Пауза').evaluate().isEmpty) break;
      trace.add((offset: position.pixels, y: _cursorY(tester)));
    }

    final phase1 = trace.where((t) => t.offset == 0).toList();
    final phase2 =
        trace.where((t) => t.offset > 0 && t.offset < max - 0.5).toList();
    final phase3 = trace.where((t) => t.offset >= max - 0.5).toList();

    expect(phase1, isNotEmpty);
    for (final t in phase1) {
      expect(t.y, lessThan(f40 + 1), reason: 'фаза 1: индикатор выше 40%');
    }

    expect(phase2, isNotEmpty);
    for (final t in phase2) {
      expect(t.y, closeTo(f40, 1), reason: 'фаза 2: индикатор на 40%');
    }

    expect(phase3.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < phase3.length; i++) {
      expect(
        phase3[i].y,
        greaterThanOrEqualTo(phase3[i - 1].y - 0.001),
        reason: 'фаза 3: индикатор едет вниз',
      );
    }
    expect(phase3.last.y, greaterThan(f40 + 5),
        reason: 'фаза 3: индикатор уехал ниже 40%');

    expect(find.byTooltip('Автоскролл'), findsOneWidget);
    expect(position.pixels, closeTo(max, 0.5));
  });

  testWidgets('каунтдаун перед стартом автоскролла', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_lines(60)), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.byTooltip('Пауза'), findsOneWidget);
  });

  testWidgets('смена скорости влияет на автоскролл на лету', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_lines(60), scrollSpeed: 30), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    for (var i = 0; i < 40 && position.pixels <= 0; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(position.pixels, greaterThan(0));

    final beforeFast = position.pixels;
    await tester.pump(const Duration(seconds: 4));
    final fastDelta = position.pixels - beforeFast;
    expect(fastDelta, greaterThan(0));

    final slower = find.byTooltip('Медленнее');
    for (var i = 0; i < 10; i++) {
      await tester.tap(slower);
      await tester.pump();
    }
    expect(find.text('20 строк/мин'), findsOneWidget);

    final beforeSlow = position.pixels;
    await tester.pump(const Duration(seconds: 4));
    final slowDelta = position.pixels - beforeSlow;

    expect(slowDelta, lessThan(fastDelta - 5));
  });

  testWidgets('пустая песня: автоскролл сам останавливается', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(''), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('Автоскролл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('текст короче экрана: автоскролл сразу завершается', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song('одна строка'), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 1));

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    expect(find.byTooltip('Автоскролл'), findsOneWidget);
    expect(position.pixels, 0);
  });
}
