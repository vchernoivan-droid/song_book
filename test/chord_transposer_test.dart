import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/chord_transposer.dart';
import 'package:song_book/services/song_parser.dart';

/// Все имена аккордов модели по порядку, в тональности самой песни.
List<String> chordNames(ParsedSong song) => [
      for (final s in song.sections)
        for (final l in s.lines)
          for (final t in l.tokens)
            if (t is SyllableToken && t.chord != null)
              t.chord!.display(song.tonic, song.tonicName)
            else if (t is ChordToken)
              t.chord.display(song.tonic, song.tonicName),
    ];

void main() {
  group('смена тоники (transposed)', () {
    test('0 полутонов — та же модель', () {
      final song = parseSong('Am F\nтекст\n');
      expect(song.transposed(0), same(song));
    });

    test('+12 полутонов — те же имена', () {
      expect(chordNames(parseSong('Am F\n').transposed(12)), ['Am', 'F']);
    });

    test('аккорды слогов, доп. смены и хвосты строки', () {
      final t =
          parseSong('Am  Dm         E7  A7\nслова строки\n').transposed(1);
      expect(chordNames(t), ['Bbm', 'Ebm', 'F7', 'Bb7']);
    });

    test('прогрессия рендерится с новыми именами', () {
      expect(renderSong(parseSong('Am   F   C   G\n').transposed(2)),
          'Bm   G   D   A\n');
    });

    test('качества аккордов сохраняются', () {
      final t = parseSong('Am7 F#m7 Cmaj7 Dsus4 Bdim\n').transposed(1);
      expect(chordNames(t),
          ['Bbm7', 'Gm7', 'C#maj7', 'Ebsus4', 'Cdim']);
    });

    test('слэш-аккорды транспонируют бас', () {
      final t = parseSong('C/G  G/B\n').transposed(2);
      expect(chordNames(t), ['D/A', 'A/C#']);
    });

    test('энгармоника: C#, F# — диезы; Eb, Ab, Bb — бемоли', () {
      final t = parseSong('C  F  G  D  A  Bb  A#\n').transposed(1);
      expect(chordNames(t),
          ['C#', 'F#', 'Ab', 'Eb', 'Bb', 'B', 'B']);
    });

    test('отрицательное смещение через ноль', () {
      expect(chordNames(parseSong('C\nF#\n').transposed(-1)), ['B', 'F']);
    });

    test('тоника рендерится написанным именем', () {
      expect(renderSong(parseSong('G#7~A7\n')), 'G#7~A7\n');
      expect(renderSong(parseSong('G#7~A7\n').transposed(1)), 'A7~Bb7\n');
    });

    test('текст песни не трогаем', () {
      final song = parseSong('On a dark desert highway\nAm I wrong\n');
      final t = song.transposed(3);
      expect(chordNames(t), isEmpty);
      expect(renderSong(t), renderSong(song));
    });

    test('табулатуры не трогаем', () {
      const tab = 'e|-------0---------------|';
      expect(renderSong(parseSong(tab).transposed(5)), '$tab\n');
    });

    test('аккорд внутри inline-комментария транспонируется', () {
      const content =
          'G        C           // you can do C7 here\nГоворит, послухайте\n';
      final t = parseSong(content).transposed(2);
      expect(chordNames(t), contains('D7'));
      expect(renderSong(t), contains('// you can do D7  here'));
    });

    test('аннотация строки текста не трогается', () {
      final line = parseSong('Припев (2 раза)\n')
          .transposed(5)
          .sections
          .single
          .lines
          .single;
      expect(line.tokens.whereType<AnnotationToken>().single,
          const AnnotationToken('(2 раза)'));
    });

    test('кириллический двойник транспонируется как обычный аккорд', () {
      expect(chordNames(parseSong('С7 Am\n').transposed(2)), ['D7', 'Bm']);
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
      final result = renderSong(parseSong(content).transposed(1));
      expect(result, contains('[Вступление]'));
      expect(result, contains('Bbm'));
      expect(result, contains('On a dark desert highway'));
      expect(result, contains('e|-------0---------------|'));
    });
  });

  group('replaceChordContent', () {
    test('заменяет аккорд и считает замены', () {
      final r = replaceChordContent(
          'Am F C Am', parseChord('Am')!, parseChord('Bm')!);
      expect(r.content, 'Bm F C Bm');
      expect(r.count, 2);
    });

    test('изменение длины компенсируется пробелами', () {
      final r = replaceChordContent(
          'Am   F   Am', parseChord('Am')!, parseChord('Bbm')!);
      expect(r.content, 'Bbm  F   Bbm');
      expect(r.count, 2);
    });

    test('не трогает другие аккорды с той же тоникой', () {
      final r = replaceChordContent(
          'Am7 Am A', parseChord('Am')!, parseChord('Bm')!);
      expect(r.content, 'Am7 Bm A');
      expect(r.count, 1);
    });

    test('текст и табулатуры не трогаем', () {
      const content = 'Am   F\nOn a dark highway\ne|--0--|\n';
      final r =
          replaceChordContent(content, parseChord('Am')!, parseChord('Bm')!);
      expect(r.content, 'Bm   F\nOn a dark highway\ne|--0--|\n');
      expect(r.count, 1);
    });

    test('from == to — без изменений', () {
      final r = replaceChordContent(
          'Am F', parseChord('Am')!, parseChord('Am')!);
      expect(r.content, 'Am F');
      expect(r.count, 0);
    });
  });
}
