part of 'song_parser.dart';

// Лексер не классифицирует строки; решения — в парсере.
sealed class Lex {
  const Lex(this.start, this.end);

  final int start;
  final int end;
}

// rootName — нормализованное латинское написание («С7» → «C7»).
class ChordLex extends Lex {
  final PitchChord chord;
  final String rootName;

  const ChordLex(this.chord, this.rootName, super.start, super.end);
}

class WordLex extends Lex {
  final String text;
  const WordLex(this.text, super.start, super.end);
}

class SymbolLex extends Lex {
  final String text;
  const SymbolLex(this.text, super.start, super.end);
}

// Кириллические двойники и H-нотацию (Н=B) ловим в regex; стопоры не дают слипнуться со словами.
final RegExp _lexRe = RegExp(
  '(?<![\\p{L}\\p{N}])'
  '([A-GАВСЕHН])([#b♯♭]?)'
  '((?:maj|min|sus|dim|aug|add|alt|mM|m|M|°|º|ø|Δ|\\+|-|#|b|\\d|\\(|\\))*)'
  '(?:/([A-GАВСЕHН])([#b♯♭]?))?'
  '(?![\\p{L}\\p{N}])'
  '|([\\p{L}\\p{N}]+)'
  '|([^\\s\\p{L}\\p{N}]+)',
  unicode: true,
);

final RegExp _dotRunRe = RegExp(r'^\.+$');

List<Lex> lexLine(String line, {bool skipPeriods = false}) {
  final lex = <Lex>[];
  for (final m in _lexRe.allMatches(line)) {
    if (m[1] != null) {
      lex.add(ChordLex(_chordFromMatch(m), _rootName(m), m.start, m.end));
    } else if (m[6] != null) {
      lex.add(WordLex(m[6]!, m.start, m.end));
    } else if (skipPeriods && _dotRunRe.hasMatch(m[7]!)) {
      continue;
    } else {
      lex.add(SymbolLex(m[7]!, m.start, m.end));
    }
  }
  return lex;
}

List<({String text, int start})> _runsOf(String line, List<Lex> lex) {
  final runs = <({String text, int start})>[];
  var buf = StringBuffer();
  int? start;
  var prevEnd = -1;
  for (final l in lex) {
    if (start != null && l.start > prevEnd) {
      runs.add((text: buf.toString(), start: start));
      buf = StringBuffer();
      start = null;
    }
    start ??= l.start;
    buf.write(line.substring(l.start, l.end));
    prevEnd = l.end;
  }
  if (start != null) runs.add((text: buf.toString(), start: start));
  return runs;
}

({List<Lex> head, String? annotation}) _lyricSplit(String line) {
  final lex = lexLine(line);
  var headRuns = 0;
  var prevEnd = -1;
  for (final l in lex) {
    final startsRun = l.start > prevEnd;
    prevEnd = l.end;
    if (!startsRun) continue;
    final dashOnly = l is SymbolLex && _dashTokenRe.hasMatch(l.text);
    final wordStart = l is WordLex || l is ChordLex;
    // Хвост-аннотация — первый символьный кусок после слов.
    if (!wordStart && !dashOnly && headRuns > 0) {
      return (head: lex.sublist(0, lex.indexOf(l)), annotation: line.substring(l.start));
    }
    headRuns++;
  }
  return (head: lex, annotation: null);
}

// Двойники латинских из-за раскладки; индексы синхронны с _lookalikeLatin.
const String _lookalikeCyrillic = 'АВЕКМНОРСТУХ';
const String _lookalikeLatin = 'ABEKMHOPCTYX';

String _normalizeRootLetter(String letter) {
  final i = _lookalikeCyrillic.indexOf(letter);
  return i == -1 ? letter : _lookalikeLatin[i];
}

String _rootName(Match m) =>
    _normalizeRootLetter(m[1]!) + (m[2] ?? '');

PitchChord? parseChord(String token) {
  final m = _lexRe.firstMatch(token);
  if (m == null || m[1] == null || m.start != 0 || m.end != token.length) {
    return null;
  }
  return _chordFromMatch(m);
}

PitchChord _chordFromMatch(Match m) => PitchChord(
      root: _pitchOf(_normalizeRootLetter(m[1]!) + (m[2] ?? '')),
      quality: m[3] ?? '',
      bass: m[4] == null
          ? null
          : _pitchOf(_normalizeRootLetter(m[4]!) + (m[5] ?? '')),
    );

// Ловушка: «А»/«В»/«С»/«Am» в словесной позиции — слово, не аккорд.
bool _isWordTrap(ChordLex c, String line, List<Lex> lex) {
  final single = c.rootName.length == 1 && c.chord.quality.isEmpty;
  final isAm =
      c.rootName == 'A' && c.chord.quality == 'm' && c.chord.bass == null;
  if (!single && !isAm) return false;

  final before = line.substring(0, c.start).replaceAll(RegExp(r'\s'), '');
  if (before.isNotEmpty && !before.endsWith('.')) return false;

  return lex
      .where((l) => l.start >= c.end)
      .whereType<WordLex>()
      .any((w) => RegExp(r'\p{L}{2}', unicode: true).hasMatch(w.text));
}

final RegExp _tabLineStart = RegExp(r'^(e|B|G|D|A|E)\s*\|');

bool isTabLineText(String line) {
  final t = line.trimLeft();
  return _tabLineStart.hasMatch(t) || t.startsWith('----');
}

// Дефисы/тире — пунктуация текста, не хвост-аннотация.
final RegExp _dashTokenRe = RegExp(r'^[-‒–—―−]+$');

// Строка аккордная, если есть аккорды; одиночная «ловушка» — текстовая.
bool isChordLineText(String line) {
  final lex = lexLine(line);
  final chords = lex.whereType<ChordLex>().toList();
  if (chords.isEmpty) return false;
  if (chords.length == 1 && _isWordTrap(chords.single, line, lex)) {
    return false;
  }
  return true;
}
