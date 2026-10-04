import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/song_listen_logger.dart';

void main() {
  test('localeIdFor по алфавиту текста', () {
    expect(SongListenLogger.localeIdFor('Я иду на ледоколе'), 'ru-RU');
    expect(SongListenLogger.localeIdFor('I see trees of green'), 'en-US');
    expect(SongListenLogger.localeIdFor('123 ... 456'), isNull);
    expect(SongListenLogger.localeIdFor('Привет world'), 'ru-RU');
  });
}
