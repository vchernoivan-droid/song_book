import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/models/song.dart';
import 'package:song_book/models/song_defaults.dart';

// Лёгкие unit-тесты без плагинов (path_provider в тестах недоступен).

void main() {
  test('Song.preview возвращает первую непустую строку', () {
    const song = Song(
      fileName: 'Test.txt',
      title: 'Test',
      content: '\n\nHello world\nSecond line',
    );
    expect(song.preview, 'Hello world');
  });

  test('Song.preview для пустого контента — «Пусто»', () {
    const song = Song(fileName: 'Empty.txt', title: 'Empty', content: '   \n\n');
    expect(song.preview, 'Пусто');
  });

  group('шапка транспонирования', () {
    test('fromRaw без шапки — transpose 0, текст как есть', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: 'Am F\nТекст',
      );
      expect(song.transpose, 0);
      expect(song.content, 'Am F\nТекст');
    });

    test('fromRaw с положительной шапкой', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# transpose: +4\nAm F',
      );
      expect(song.transpose, 4);
      expect(song.content, 'Am F');
    });

    test('fromRaw с отрицательной шапкой', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# transpose: -3\nAm F',
      );
      expect(song.transpose, -3);
    });

    test('значение за пределами ±11 обрезается', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# transpose: +99\nAm F',
      );
      expect(song.transpose, 11);
    });

    test('шапка не на первой строке игнорируется', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: 'Am F\n# transpose: +4',
      );
      expect(song.transpose, 0);
      expect(song.content, 'Am F\n# transpose: +4');
    });

    test('шапку транспонирования не пишем — состояние в тональности тела', () {
      const song = Song(
        fileName: 'A.txt',
        title: 'A',
        content: 'Am F',
        transpose: 4,
      );
      expect(song.rawContent, 'Am F');
    });

    test('rawContent при нуле — без шапки', () {
      const song = Song(fileName: 'A.txt', title: 'A', content: 'Am F');
      expect(song.rawContent, 'Am F');
    });

    test('fromRaw читает шапку шрифта', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# font: 18\nAm F',
      );
      expect(song.fontSize, 18);
      expect(song.content, 'Am F');
    });

    test('fromRaw читает обе шапки в любом порядке', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# font: 18\n# transpose: +2\nAm F',
      );
      expect(song.transpose, 2);
      expect(song.fontSize, 18);
      expect(song.content, 'Am F');
    });

    test('fontSize по умолчанию', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: 'Am F',
      );
      expect(song.fontSize, defaultFontSize);
    });

    test('fontSize за пределами 10..28 обрезается', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# font: 99\nAm F',
      );
      expect(song.fontSize, 28);
    });

    test('rawContent пишет шапку шрифта при отличии от дефолта', () {
      const song = Song(
        fileName: 'A.txt',
        title: 'A',
        content: 'Am F',
        fontSize: 18,
      );
      expect(song.rawContent, '# font: 18\nAm F');
    });

    test('withHeaders склеивает шапки', () {
      expect(
        Song.withHeaders(fontSize: 18, body: 'Am'),
        '# font: 18\nAm',
      );
      expect(
        Song.withHeaders(fontSize: defaultFontSize, body: 'Am'),
        'Am',
      );
    });
  });
}
