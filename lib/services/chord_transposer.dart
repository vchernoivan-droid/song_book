/// Строчная замена аккордов в тексте песни — операция редактора.
///
/// Транспонирование модели — смена тоники ([ParsedSong.transposed]),
/// здесь остаётся только замена имён в сыром тексте.
library;

import 'song_parser.dart';

/// Заменяет все вхождения аккорда [from] на [to] в аккордных строках.
/// Возвращает новый текст и число замен.
({String content, int count}) replaceChordContent(
    String content, PitchChord from, PitchChord to) {
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
String _transformChordLine(String line, PitchChord Function(PitchChord) transform) {
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
