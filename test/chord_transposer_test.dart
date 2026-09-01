import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/chord_transposer.dart';
import 'package:song_book/services/song_parser.dart';

/// Все аккорды модели по порядку: слоговые (включая пустые слоги),
/// доп. смены и аккорды конца строки.
List<String> chordDisplays(ParsedSong song) => [
      for (final s in song.sections)
        for (final l in s.lines)
          for (final t in l.tokens)
            if (t is SyllableToken && t.chord != null)
              t.chord!.display
            else if (t is ChordToken)
              t.chord.display,
    ];

void main() {
  group('transposeSong', () {
    test('0 полутонов — та же модель', () {
      final song = parseSong('Am F\nтекст\n');
      expect(transposeSong(song, 0), same(song));
    });

    test('+12 полутонов — те же аккорды', () {
      expect(chordDisplays(transposeSong(parseSong('Am F\n'), 12)),
          ['Am', 'F']);
    });

    test('аккорды слогов, доп. смены и хвосты строки', () {
      final t =
          transposeSong(parseSong('Am  Dm         E7  A7\nслова строки\n'), 1);
      expect(chordDisplays(t), ['Bbm', 'Ebm', 'F7', 'Bb7']);
    });

    test('прогрессия рендерится с новыми именами', () {
      expect(renderSong(transposeSong(parseSong('Am   F   C   G\n'), 2)),
          'Bm   G   D   A\n');
    });

    test('качества аккордов сохраняются', () {
      final t =
          transposeSong(parseSong('Am7 F#m7 Cmaj7 Dsus4 Bdim\n'), 1);
      expect(chordDisplays(t),
          ['Bbm7', 'Gm7', 'C#maj7', 'Ebsus4', 'Cdim']);
    });

    test('слэш-аккорды транспонируют бас', () {
      final t = transposeSong(parseSong('C/G  G/B\n'), 2);
      expect(chordDisplays(t), ['D/A', 'A/C#']);
    });

    test('энгармоника: C#, F#, G# — диезы; Eb, Ab, Bb — бемоли', () {
      final t =
          transposeSong(parseSong('C  F  G  D  A  Bb  A#\n'), 1);
      expect(chordDisplays(t),
          ['C#', 'F#', 'Ab', 'Eb', 'Bb', 'B', 'B']);
    });

    test('отрицательное смещение через ноль', () {
      expect(chordDisplays(transposeSong(parseSong('C\nF#\n'), -1)),
          ['B', 'F']);
    });

    test('текст песни не трогаем', () {
      final song = parseSong('On a dark desert highway\nAm I wrong\n');
      final t = transposeSong(song, 3);
      expect(chordDisplays(t), isEmpty);
      expect(renderSong(t), renderSong(song));
    });

    test('табулатуры не трогаем', () {
      const tab = 'e|-------0---------------|';
      expect(renderSong(transposeSong(parseSong(tab), 5)), '$tab\n');
    });

    test('аккорд внутри inline-комментария транспонируется', () {
      const content =
          'G        C           // you can do C7 here\nГоворит, послухайте\n';
      final line = transposeSong(parseSong(content), 2)
          .sections
          .single
          .lines
          .single;
      expect(
        line.tokens.whereType<InlineToken>().single,
        const InlineToken('// you can do D7 here', endOfLine: true),
      );
    });

    test('аннотация строки текста не трогается', () {
      final line = transposeSong(parseSong('Припев (2 раза)\n'), 5)
          .sections
          .single
          .lines
          .single;
      expect(line.tokens.whereType<AnnotationToken>().single,
          const AnnotationToken('(2 раза)'));
    });

    test('кириллический двойник транспонируется как обычный аккорд', () {
      expect(chordDisplays(transposeSong(parseSong('С7 Am\n'), 2)),
          ['D7', 'Bm']);
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
      final result = renderSong(transposeSong(parseSong(content), 1));
      expect(result, contains('[Вступление]'));
      expect(result, contains('Bbm'));
      expect(result, contains('On a dark desert highway'));
      expect(result, contains('e|-------0---------------|'));
    });

    test('переходы через ~ транспонируют оба аккорда', () {
      final t = transposeSong(parseSong('G#7~A7\n'), 1);
      expect(chordDisplays(t), ['A7', 'Bb7']);
      expect(renderSong(t), 'A7~Bb7\n');
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
