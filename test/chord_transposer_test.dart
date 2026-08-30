import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/chord_transposer.dart';

void main() {
  group('transposeSongContent', () {
    test('0 полутонов — текст без изменений', () {
      const content = 'Am   F   C   G\nOn a dark desert highway';
      expect(transposeSongContent(content, 0), content);
    });

    test('+12 полутонов — те же аккорды', () {
      expect(transposeSongContent('Am F', 12), 'Am F');
    });

    test('строка аккордов транспонируется, выравнивание сохраняется', () {
      expect(transposeSongContent('Am   F   C   G', 2), 'Bm   G   D   A');
      expect(transposeSongContent('Am        F', 1), 'Bbm       F#');
      expect(transposeSongContent('Am   F', 1), 'Bbm  F#');
    });

    test('аккорд стал короче — пробелы дополняются', () {
      expect(transposeSongContent('Bbm  F#', -1), 'Am   F');
    });

    test('качества аккордов сохраняются', () {
      expect(transposeSongContent('Am7 F#m7 Cmaj7 Dsus4 Bdim', 1),
          'Bbm7 Gm7  C#maj7 Ebsus4 Cdim');
    });

    test('слэш-аккорды транспонируют бас', () {
      expect(transposeSongContent('C/G', 2), 'D/A');
      expect(transposeSongContent('G/B', 1), 'Ab/C');
    });

    test('энгармоника: C#, F#, G# — диезы; Eb, Ab, Bb — бемоли', () {
      expect(transposeSongContent('C', 1), 'C#');
      expect(transposeSongContent('F', 1), 'F#');
      expect(transposeSongContent('G', 1), 'Ab');
      expect(transposeSongContent('D', 1), 'Eb');
      expect(transposeSongContent('A', 1), 'Bb');
      expect(transposeSongContent('A#', -1), 'A');
      expect(transposeSongContent('Bb', 1), 'B');
    });

    test('отрицательное смещение через ноль', () {
      expect(transposeSongContent('C', -1), 'B');
      expect(transposeSongContent('F#', -1), 'F');
    });

    test('текст песни не трогаем', () {
      const line = 'On a dark desert highway';
      expect(transposeSongContent(line, 3), line);
      expect(transposeSongContent('Am I wrong', 3), 'Am I wrong');
    });

    test('табулатуры не трогаем', () {
      const tab = 'e|-------0---------------|\nB|-----1---1-------------|';
      expect(transposeSongContent(tab, 5), tab);
    });

    test('заголовок секции в строке аккордов остаётся как есть', () {
      expect(transposeSongContent('[Куплет 1] Am F', 2), '[Куплет 1] Bm G');
    });

    test('аккордная строка с комментарием: аккорды сдвигаются, хвост остаётся', () {
      expect(transposeSongContent('G        C           // you can do C7 here', 2),
          'A        D           // you can do D7 here');
    });

    test('кириллический двойник транспонируется как обычный аккорд', () {
      expect(transposeSongContent('С7 Am', 2), 'D7 Bm');
    });

    test('полный пример: аккорды меняются, текст и табы нет', () {
      const content = '''
[Вступление]
Am   F   C   G

[Куплет 1]
On a dark desert highway

[Табы]
e|-------0---------------|
''';
      final result = transposeSongContent(content, 1);
      expect(result, contains('[Вступление]'));
      expect(result, contains('Bbm'));
      expect(result, contains('On a dark desert highway'));
      expect(result, contains('e|-------0---------------|'));
    });

    test('переходы через ~ транспонируют оба аккорда', () {
      expect(transposeSongContent('G#7~A7', 1), 'A7~Bb7');
      expect(transposeSongContent('Em75-   G#7~A7 Dm', 1), 'Fm75-   A7~Bb7 Ebm');
    });
  });
}
