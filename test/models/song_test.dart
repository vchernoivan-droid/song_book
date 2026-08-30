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

    test('withTransposeHeader для отрицательного значения', () {
      expect(Song.withTransposeHeader(-3, 'Am'), '# transpose: -3\nAm');
    });
  });
}
