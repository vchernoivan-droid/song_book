import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/models/song.dart';

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

    test('rawContent добавляет шапку при ненулевом транспонировании', () {
      const song = Song(
        fileName: 'A.txt',
        title: 'A',
        content: 'Am F',
        transpose: 4,
      );
      expect(song.rawContent, '# transpose: +4\nAm F');
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

    test('fontSize по умолчанию 15', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: 'Am F',
      );
      expect(song.fontSize, 15);
    });

    test('fontSize за пределами 10..28 обрезается', () {
      final song = Song.fromRaw(
        fileName: 'A.txt',
        title: 'A',
        rawContent: '# font: 99\nAm F',
      );
      expect(song.fontSize, 28);
    });

    test('rawContent пишет шапку шрифта при отличии от 15', () {
      const song = Song(
        fileName: 'A.txt',
        title: 'A',
        content: 'Am F',
        fontSize: 20,
      );
      expect(song.rawContent, '# font: 20\nAm F');
    });

    test('withHeaders склеивает обе шапки', () {
      expect(Song.withHeaders(transpose: -3, fontSize: 18, body: 'Am'),
          '# transpose: -3\n# font: 18\nAm');
      expect(Song.withHeaders(transpose: 0, fontSize: 15, body: 'Am'), 'Am');
    });
  });
}
