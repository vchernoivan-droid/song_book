/// Транспонирование аккордов в тексте песни (надстрочный формат).
///
/// Строки с текстом и табулатурами не меняются. Чтобы аккорды не «уезжали»
/// со своих слов, изменение длины аккорда компенсируется пробелами после него.
library;

import 'song_parser.dart';

const Map<String, int> _letterPitch = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

/// Предпочитаемые написания полутонов: диезы для C#, F#, бемоли для Eb, Ab, Bb.
const List<String> _pitchNames = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// Транспонирует текст песни на [semitones] полутонов.
String transposeSongContent(String content, int semitones) {
  if (semitones == 0) return content;
  return content
      .split('\n')
      .map((line) => _transposeLine(line, semitones))
      .join('\n');
}

String _transposeLine(String line, int semitones) {
  if (isTabLineText(line) || !isChordLineText(line)) return line;
  return _transposeChordLine(line, semitones);
}

String _transposeChordLine(String line, int semitones) {
  final tokens = RegExp(r'\S+').allMatches(line).toList();
  final out = StringBuffer();
  var cursor = 0;
  for (var i = 0; i < tokens.length; i++) {
    final m = tokens[i];
    final token = m[0]!;
    out.write(line.substring(cursor, m.start));

    final chord = parseChord(token);
    final shifted =
        chord == null ? token : _transposeChord(chord, semitones).display;
    out.write(shifted);

    final hasNext = i + 1 < tokens.length;
    final gapEnd = hasNext ? tokens[i + 1].start : line.length;
    var gap = line.substring(m.end, gapEnd);
    gap = _absorbDelta(gap, shifted.length - token.length, hasNext);
    out.write(gap);
    cursor = gapEnd;
  }
  out.write(line.substring(cursor));
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
