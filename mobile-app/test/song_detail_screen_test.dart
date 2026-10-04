import 'dart:io';

import 'package:flutter/gestures.dart';
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

String _distinctLines() =>
    'первая строка тут\nвторая строка здесь\nтретья строка везде';

const _longWords = <String>[
  'кошка', 'собака', 'дерево', 'река', 'гора', 'море', 'небо', 'земля',
  'огонь', 'вода', 'ветер', 'камень', 'трава', 'цветок', 'птица', 'зверь',
  'дом', 'окно', 'дверь', 'крыша', 'лес', 'поле', 'луг', 'сад',
  'утро', 'вечер', 'ночь', 'день', 'солнце', 'луна', 'звезда', 'туча',
  'рука', 'нога', 'глаз', 'ухо', 'сердце', 'душа', 'мысль', 'слово',
  'путь', 'дорога', 'тропа', 'мост', 'город', 'село', 'изба', 'печь',
  'хлеб', 'молоко', 'мёд', 'сыр', 'репа', 'гриб', 'ягода', 'орех',
  'медведь', 'лиса', 'заяц', 'волк',
];

String _distinctLong() => _longWords.join('\n');

String _chordedLong() => [
      for (var i = 0; i < _longWords.length; i++) ...['Am', _longWords[i]],
    ].join('\n');

void Function(String recognizedWords)? capturedOnResult;

SongListenLogger _nullListenLogger({
  required String title,
  required int scrollSpeed,
  required int fontSize,
  required String? localeId,
  required double Function() position,
  void Function(String recognizedWords)? onResult,
}) {
  capturedOnResult = onResult;
  return _NullListenLogger();
}

class _NullListenLogger extends SongListenLogger {
  _NullListenLogger()
      : super(
          title: 'тест',
          scrollSpeed: 0,
          fontSize: 0,
          localeId: null,
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

  testWidgets('скролл следует за стрелкой до конца и не выходит за max', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
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

    for (final word in ['море', 'зверь', 'звезда', 'мёд', 'волк']) {
      capturedOnResult!(word);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(position.pixels, lessThanOrEqualTo(max + 0.001));
    }

    expect(position.pixels, closeTo(max, 0.6));
  });

  testWidgets('ручной скролл переставляет стрелку на ближайшую строку', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
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

    capturedOnResult!('зверь');
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(_cursorY(tester), closeTo(position.viewportDimension * 0.4, 0.6));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pump();
    expect(_cursorY(tester), closeTo(position.viewportDimension * 0.4, 14.0));
  });

  testWidgets('тап по стрелкиному полю переставляет стрелку на ближайшую строку', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    capturedOnResult!('зверь');
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));

    final stackTop = tester.getTopLeft(
      find.ancestor(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Stack),
      ),
    );
    await tester.tapAt(stackTop + const Offset(20, 400));
    await tester.pump();
    expect(_cursorY(tester), closeTo(400, 14.0));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(_cursorY(tester), closeTo(position.viewportDimension * 0.4, 0.6));
  });

  testWidgets('тап создаёт стрелку, когда матча ещё не было', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(_cursorPaint(), findsNothing);

    final stackTop = tester.getTopLeft(
      find.ancestor(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Stack),
      ),
    );
    await tester.tapAt(stackTop + const Offset(20, 400));
    await tester.pump();
    expect(_cursorPaint(), findsOneWidget);
    expect(_cursorY(tester), closeTo(400, 14.0));
  });

  testWidgets('колесо-скролл ставит стрелку на ближайшую строку', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
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
    expect(_cursorPaint(), findsNothing);

    await tester.sendEventToBinding(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(SingleChildScrollView)),
      scrollDelta: const Offset(0, 200),
    ));
    await tester.pump();
    await tester.pump();
    expect(position.pixels, closeTo(200, 15));

    expect(_cursorPaint(), findsOneWidget);
    expect(_cursorY(tester), closeTo(position.viewportDimension * 0.4, 14.0));
  });

  testWidgets('тап в песне с аккордами ставит стрелку на ближайшую лирическую строку', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_chordedLong()), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Автоскролл'));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final stackTop = tester.getTopLeft(
      find.ancestor(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Stack),
      ),
    );
    await tester.tapAt(stackTop + const Offset(20, 400));
    await tester.pump();
    expect(_cursorPaint(), findsOneWidget);
    expect(_cursorY(tester), closeTo(400, 27.0));
  });

  testWidgets('в начале песни не скроллим, пока стрелка выше 40%', (tester) async {
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

    capturedOnResult!('строка 2');
    await tester.pump();
    expect(position.pixels, 0);
    expect(_cursorY(tester), closeTo(16 + 2 * 27 + 13.5, 4.0));
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

    Color? colorOf(String n) => tester.widget<Text>(find.text(n)).style?.color;

    expect(find.text('3'), findsOneWidget);
    expect(colorOf('3'), Colors.red.shade600);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    expect(colorOf('2'), Colors.amber.shade900);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(colorOf('1'), Colors.green.shade600);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.byTooltip('Пауза'), findsOneWidget);
  });

  testWidgets('скролл-зона растянута на всю ширину экрана', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SongDetailScreen(song: _song(_distinctLong()), listenLoggerFactory: _nullListenLogger)),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(SingleChildScrollView)).width, 1280);
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

  testWidgets('короткая песня: автоскролл активен и не скроллит', (tester) async {
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

    expect(find.byTooltip('Пауза'), findsOneWidget);
    expect(position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  group('стрелка певца', () {
    Future<void> startAutoScroll(WidgetTester tester, String content) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SongDetailScreen(
              song: _song(content), listenLoggerFactory: _nullListenLogger),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Автоскролл'));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('встаёт на строку, мусор не двигает, назад двигает', (tester) async {
      await startAutoScroll(tester, _distinctLines());
      expect(_cursorPaint(), findsNothing);
      capturedOnResult!('вторая строка здесь');
      await tester.pump();
      expect(_cursorPaint(), findsOneWidget);
      expect(_cursorY(tester), closeTo(16 + 27 + 13.5, 4));
      final y = _cursorY(tester);
      capturedOnResult!('ыыы чпок щщщ');
      await tester.pump();
      expect(_cursorY(tester), y);
      capturedOnResult!('первая строка тут');
      await tester.pump();
      expect(_cursorY(tester), closeTo(16 + 13.5, 4));
      capturedOnResult!('третья строка везде');
      await tester.pump();
      expect(_cursorY(tester), closeTo(16 + 2 * 27 + 13.5, 4));
    });

    testWidgets('стрелка на середине текстового ряда при аккордах', (tester) async {
      await startAutoScroll(
          tester, 'первая строка тут\nG\nвторая строка здесь\nтретья строка везде');
      capturedOnResult!('вторая строка здесь');
      await tester.pump();
      expect(_cursorY(tester), closeTo(16 + 2 * 27 + 13.5, 4));
      capturedOnResult!('третья строка везде');
      await tester.pump();
      expect(_cursorY(tester), closeTo(16 + 3 * 27 + 13.5, 4));
    });

    testWidgets('пауза автоскролла не сбрасывает стрелку', (tester) async {
      await startAutoScroll(tester, _lines(60));
      capturedOnResult!('строка 5');
      await tester.pump();
      expect(_cursorPaint(), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -150),
      );
      await tester.pump();
      expect(_cursorPaint(), findsOneWidget);
    });

    testWidgets('тишина 15 секунд сбрасывает стрелку', (tester) async {
      await startAutoScroll(tester, _distinctLines());
      capturedOnResult!('вторая строка здесь');
      await tester.pump();
      expect(_cursorPaint(), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(_cursorPaint(), findsNothing);
    });

    testWidgets('в середине песни стрелка держится на 40%', (tester) async {
      await startAutoScroll(tester, _lines(60));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      capturedOnResult!('строка 30');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      capturedOnResult!('строка 30');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(_cursorY(tester), closeTo(position.viewportDimension * 0.4, 0.6));
    });

    testWidgets('рестарт: прыжок назад скроллит вверх', (tester) async {
      await startAutoScroll(tester, _distinctLong());
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      capturedOnResult!('мёд');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(position.pixels, greaterThan(0));
      capturedOnResult!('кошка');
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(position.pixels, closeTo(0, 0.6));
    });
  });
}
