import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/lyric_locator.dart';
import 'package:song_book/services/song_parser.dart';

const ledokol = '''
Я иду на ледоколе,
Ледокол идет по льду.
То, трудяга, поле колет,
То ледовую гряду.
То прокуренною глоткой
Крикнет, жалуясь в туман,
То зовет с метеосводкой
Город Мурманск, то есть Мурманск.

И какое б продвиженье
Не имели б мы во льдах,
Знают наше положенье,
Все окрестные суда,
Даже спутник с неба целит,
В обьективы нас берет,
Смотрит, как для мирных целей
Мы долбаем крепкий лед.

И какой-нибудь подводник,
С бакенбардами, брюнет,
Наш маршрут во льдах проводит,
Навалившись на планшет,
У подводника гитара
И ракет большой запас
И мурлычет, как котяра,
Гирокомпас, то есть компас.

Но никто из них не видет
В чудо-технику свою,
Что нетрезвый, как Овидий
Я на палубе стою,
Что прогноз опровергая,
Штормы весело трубят,
Что печально, дорогая,
Жить на свете без тебя.
''';

const chorusSong = '''
[Куплет 1]
первая строка один
вторая строка один

[Припев]
общий припев строка
общий припев вторая

[Куплет 2]
первая строка два
вторая строка два

[Припев]
общий припев строка
общий припев вторая
''';

const chordSong = '''
[Вступление]
G

[Куплет]
G
Генерал-аншеф Раевский
C            D
Сам сидит на взгорье
''';

void main() {
  group('phoneticKey', () {
    test('гласные и оглушение конца', () {
      expect(LyricLocator.phoneticKey('Год'), 'гат');
      expect(LyricLocator.phoneticKey('дуб'), 'дуп');
      expect(LyricLocator.phoneticKey('Ёлка'), 'илка');
    });

    test('дефис и ь выкидываются', () {
      expect(LyricLocator.phoneticKey('Генерал-аншеф'), 'гинираланшиф');
      expect(LyricLocator.phoneticKey('льдина'), 'лдина');
    });

    test('keysOf режет пунктуацию и пустоту', () {
      expect(LyricLocator.keysOf('  Ёлка, ёлка! ... '), ['илка', 'илка']);
      expect(LyricLocator.keysOf(''), isEmpty);
    });
  });

  group('locate', () {
    final locator = LyricLocator(parseSong(ledokol.trim()));

    test('точный хвост → строка', () {
      expect(locator.locate(LyricLocator.keysOf('Ледокол идет по льду')), 1);
      expect(locator.locate(LyricLocator.keysOf('Жить на свете без тебя')), 31);
    });

    test('искажённый хвост из реального распознавания', () {
      final tail = LyricLocator.keysOf(
          'стою что прогноз дорогая бури весело рубеж что');
      expect(locator.locate(tail), 30);
    });

    test('мусор → null, пусто → null', () {
      expect(locator.locate(LyricLocator.keysOf('ыыы щщ чпок')), isNull);
      expect(locator.locate(const []), isNull);
    });

    test('догон вперёд через полпесни', () {
      expect(
        locator.locate(
          LyricLocator.keysOf('Жить на свете без тебя'),
          previousLine: 0,
        ),
        31,
      );
    });

    test('возврат назад, когда впереди нет кандидатов', () {
      expect(
        locator.locate(
          LyricLocator.keysOf('Ледокол идет по льду'),
          previousLine: 31,
        ),
        1,
      );
    });
  });

  group('стык куплета с бубнением (живые хвосты)', () {
    final locator = LyricLocator(parseSong(ledokol.trim()));

    test('мусорное слово после последней строки куплета не двигает строку', () {
      final tail = LyricLocator.keysOf('Город Мурманск, то есть Мурманск барам');
      expect(locator.locate(tail, previousLine: 7), 7);
    });

    test('гирлянда из бубнения и первого слова следующего куплета', () {
      final tail =
          LyricLocator.keysOf('Мурманск то есть Мурманск барам пампам парам пампам и');
      expect(locator.locate(tail, previousLine: 7), 7);
    });

    test('хвост с началом новой строки продвигает на неё', () {
      final tail = LyricLocator.keysOf('не имели за нашим положением все ок');
      expect(locator.locate(tail, previousLine: 10), 11);
    });

    test('чистое бубнение → null', () {
      final tail = LyricLocator.keysOf('парам пампам парам пампам');
      expect(locator.locate(tail, previousLine: 7), isNull);
    });
  });

  group('повторы: полоса вокруг previousLine', () {
    final locator = LyricLocator(parseSong(chorusSong.trim()));

    test('полный припев после первого куплета → первое вхождение', () {
      final tail = LyricLocator.keysOf('общий припев строка общий припев вторая');
      expect(locator.locate(tail, previousLine: 1), 3);
    });

    test('начало припева после второго куплета → второе вхождение', () {
      final tail = LyricLocator.keysOf('общий припев строка');
      expect(locator.locate(tail, previousLine: 5), 6);
    });
  });

  group('индексация', () {
    test('кто-то из слогов склеивается', () {
      final locator = LyricLocator(parseSong('Кто-то вспомнил меня'));
      expect(locator.locate(LyricLocator.keysOf('кто-то вспомнил меня')), 0);
    });

    test('lineCount совпадает с renderSongLines, прогрессия занимает индекс', () {
      final song = parseSong(chordSong.trim());
      final locator = LyricLocator(song);
      expect(locator.lineCount, renderSongLines(song).lines.length);
      expect(locator.locate(LyricLocator.keysOf('Сам сидит на взгорье')), 2);
    });
  });
}
