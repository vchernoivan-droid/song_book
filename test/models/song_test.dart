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
}
