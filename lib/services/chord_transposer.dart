/// Транспонирование модели песни и замена аккордов в тексте.
///
/// [transposeSong] работает с моделью ([ParsedSong]): аккорды живут
/// в токенах, транспонирование — замена [Chord] на сдвинутый; строки без
/// аккордов (текст, табулатуры) не меняются. [replaceChordContent] —
/// строчная замена для редактора текста.
library;

import 'song_parser.dart';

const Map<String, int> _letterPitch = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

/// Предпочитаемые написания полутонов: диезы для C#, F#, бемоли для Eb, Ab, Bb.
const List<String> _pitchNames = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// Транспонирует модель песни на [semitones] полутонов.
ParsedSong transposeSong(ParsedSong song, int semitones) {
  if (semitones == 0) return song;
  return ParsedSong([
    for (final s in song.sections)
      Section(
        title: s.title,
        kind: s.kind,
        lines: [
          for (final l in s.lines)
            Line([for (final t in l.tokens) _transposeToken(t, semitones)]),
        ],
      ),
  ]);
}

Token _transposeToken(Token t, int semitones) => switch (t) {
      SyllableToken(:final text, :final dash, :final chord) => SyllableToken(
          text,
          dash: dash,
          chord: chord == null ? null : _transposeChord(chord, semitones),
        ),
      ChordToken(:final chord, :final endOfLine) =>
        ChordToken(_transposeChord(chord, semitones), endOfLine: endOfLine),
      InlineToken(:final text, :final endOfLine) =>
        InlineToken(_transposeChordText(text, semitones), endOfLine: endOfLine),
      AnnotationToken() || RawToken() => t,
    };

/// Аккорды внутри inline-текста («// можно C7») транспонируются вместе со
/// всеми; текст без аккордов возвращается как есть.
String _transposeChordText(String text, int semitones) {
  final out = StringBuffer();
  for (final p in scanChordLine(text)) {
    if (p is ChordPiece) {
      out.write(_transposeChord(p.chord, semitones).display);
    } else {
      out.write((p as GapPiece).text);
    }
  }
  return out.toString();
}

/// Заменяет все вхождения аккорда [from] на [to] в аккордных строках.
/// Возвращает новый текст и число замен.
({String content, int count}) replaceChordContent(
    String content, Chord from, Chord to) {
  if (from == to) return (content: content, count: 0);
  var count = 0;
  final result = content.split('\n').map((line) {
    if (isTabLineText(line) || !isChordLineText(line)) return line;
    return _transformChordLine(line, (c) {
      if (c == from) {
        count++;
        return to;
      }
      return c;
    });
  }).join('\n');
  return (content: result, count: count);
}

/// Перебирает аккорды строки, применяет [transform] и пересобирает
/// строку, компенсируя изменение длины имён пробелами: накопленная
/// невязка поглощается хвостовыми пробелами зазора — в том числе за
/// inline-кусками вроде «~ », — чтобы аккорды не уезжали со своих
/// колонок. Остаток, который погасить негде (склеенные аккорды, конец
/// строки), просто сдвигает всё дальнейшее.
String _transformChordLine(String line, Chord Function(Chord) transform) {
  final pieces = scanChordLine(line);
  final out = StringBuffer();
  var pending = 0;
  for (var i = 0; i < pieces.length; i++) {
    final p = pieces[i];
    if (p is ChordPiece) {
      final replaced = transform(p.chord);
      out.write(replaced.display);
      pending += replaced.display.length - (p.end - p.start);
      continue;
    }
    final gap = (p as GapPiece).text;
    final head = gap.trimRight();
    final ws = gap.substring(head.length);
    if (pending != 0 && ws.isNotEmpty) {
      final adjusted = _absorbDelta(ws, pending, i + 1 < pieces.length);
      pending += adjusted.length - ws.length;
      out.write(head + adjusted);
    } else {
      out.write(gap);
    }
  }
  return out.toString();
}

/// Аккорд стал длиннее — укорачиваем пробелы после него (минимум один
/// перед следующим аккордом); стал короче — дополняем пробелами, кроме
/// последнего аккорда в строке (хвостовой пробел не нужен).
String _absorbDelta(String gap, int delta, bool hasNextToken) {
  if (delta > 0) {
    final minLen = hasNextToken ? 1 : 0;
    final removable = gap.length - minLen;
    if (removable <= 0) return gap;
    final cut = delta < removable ? delta : removable;
    return gap.substring(0, gap.length - cut);
  }
  if (delta < 0 && hasNextToken) return ' ' * -delta + gap;
  return gap;
}

Chord _transposeChord(Chord chord, int semitones) => Chord(
      root: _shiftPitch(chord.root, semitones),
      quality: chord.quality,
      bass: chord.bass == null ? null : _shiftPitch(chord.bass!, semitones),
    );

String _shiftPitch(String root, int semitones) {
  final letter = root.substring(0, 1);
  final accidental = root.length > 1 ? root.substring(1) : '';
  var pitch = _letterPitch[letter]!;
  if (accidental == '#' || accidental == '♯') pitch += 1;
  if (accidental == 'b' || accidental == '♭') pitch -= 1;
  pitch = ((pitch + semitones) % 12 + 12) % 12;
  return _pitchNames[pitch];
}
