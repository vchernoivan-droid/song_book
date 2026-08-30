/// Парсер песни из «надстрочного» формата (аккорды строкой над текстом)
/// в структурную модель и рендер обратно.
///
/// Модель: ParsedSong → Section[] → Line[] → Token[] (Word | Chord | Raw |
/// Annotation). Пара физических строк «аккорды над текстом» склеивается в
/// одну [Line]: первый аккорд слова — поле WordToken.chord (округление к
/// началу слова), дополнительные смены на слове — ChordToken сразу после
/// него, аккорды за концом слов — ChordToken(endOfLine) в конце списка.
/// Хвосты-аннотации («// можно C7», «(2 раза)») — AnnotationToken с флагом
/// строки-хозяина. Колонки и пробелы не
/// хранятся: нетронутая строка помнит исходный текст ([Line.source]) и
/// рендерится байт-в-байт; изменённая собирается заново — аккорды над
/// началами слов.
library;

/// Разновидность секции — по ключевым словам заголовка.
enum SectionKind { verse, chorus, bridge, intro, outro, solo, unknown }

/// Аккорд: тоника + качество + опциональный слэш-бас.
class Chord {
  final String root;
  final String quality;
  final String? bass;

  const Chord({required this.root, this.quality = '', this.bass});

  String get display => bass == null ? '$root$quality' : '$root$quality/$bass';

  @override
  bool operator ==(Object other) =>
      other is Chord &&
      other.root == root &&
      other.quality == quality &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(root, quality, bass);

  @override
  String toString() => display;
}

sealed class Token {
  const Token();
}

class WordToken extends Token {
  final String text;

  /// Первый аккорд слова (смена на его начале).
  final Chord? chord;

  const WordToken(this.text, {this.chord});

  @override
  bool operator ==(Object other) =>
      other is WordToken && other.text == text && other.chord == chord;

  @override
  int get hashCode => Object.hash(text, chord);
}

class ChordToken extends Token {
  final Chord chord;

  /// Аккорд за пределами слов строки — рендерится после последнего слова,
  /// а не над началом своего.
  final bool endOfLine;

  const ChordToken(this.chord, {this.endOfLine = false});

  @override
  bool operator ==(Object other) =>
      other is ChordToken &&
      other.chord == chord &&
      other.endOfLine == endOfLine;

  @override
  int get hashCode => Object.hash(chord, endOfLine);
}

class RawToken extends Token {
  final String text;
  const RawToken(this.text);

  @override
  bool operator ==(Object other) => other is RawToken && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class AnnotationToken extends Token {
  /// Хвостовая пометка строки текста («(2 раза)»).
  final String text;

  const AnnotationToken(this.text);

  @override
  bool operator ==(Object other) => other is AnnotationToken && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class InlineToken extends Token {
  /// Не-аккордный кусок аккордной строки: «~» между аккордами
  /// (endOfLine: false) или хвостовая пометка после аккордов
  /// («2x», «// комментарий», endOfLine: true).
  final String text;

  final bool endOfLine;

  const InlineToken(this.text, {this.endOfLine = false});

  @override
  bool operator ==(Object other) =>
      other is InlineToken &&
      other.text == text &&
      other.endOfLine == endOfLine;

  @override
  int get hashCode => Object.hash(text, endOfLine);
}

/// Строка песни. Слитная пара «аккорды + текст» — одна [Line]: первый
/// аккорд слова — в поле [WordToken.chord], дополнительные смены на слове —
/// [ChordToken] сразу после него, аккорды за концом слов — в конце списка
/// с [ChordToken.endOfLine].
class Line {
  final List<Token> tokens;
  final String? source;

  const Line(this.tokens, {this.source});

  /// Строка без слов (интро, проигрыш без текста): аккорды, inline-куски
  /// и хвостовые аннотации.
  bool get isProgression =>
      tokens.isNotEmpty && tokens.every((t) => t is! WordToken);
}

class Section {
  /// Распознанный текст заголовка («Куплет 1»); null — блока без заголовка.
  final String? title;

  /// Заголовок как в исходнике («[Куплет 1]», «Припев:»); null — нет.
  final String? titleSource;

  final SectionKind kind;
  final List<Line> lines;

  const Section({
    this.title,
    this.titleSource,
    this.kind = SectionKind.unknown,
    required this.lines,
  });
}

class ParsedSong {
  final List<Section> sections;

  const ParsedSong(this.sections);
}

// ---------------------------------------------------------------------------
// Парсинг
// ---------------------------------------------------------------------------

/// Разбирает текст песни (без служебной шапки транспонирования).
ParsedSong parseSong(String content) {
  final sections = <Section>[];
  final block = <String>[];

  void flush() {
    if (block.isEmpty) return;
    sections.add(_parseSection(block));
    block.clear();
  }

  for (final line in content.split('\n')) {
    if (line.trim().isEmpty) {
      flush();
    } else {
      block.add(line);
    }
  }
  flush();
  return ParsedSong(sections);
}

Section _parseSection(List<String> block) {
  final header = _parseHeader(block.first);
  final rest = header == null ? block : block.sublist(1);
  return Section(
    title: header?.title,
    titleSource: header?.source,
    kind: header?.kind ?? SectionKind.unknown,
    lines: _parseLines(rest),
  );
}

/// Распознаёт строку-заголовок: «[Куплет 1]» (всегда) или «Припев:»
/// (только если внутри есть ключевое слово секции).
({String title, String source, SectionKind kind})? _parseHeader(String line) {
  final bracket = RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(line);
  final colon =
      bracket == null ? RegExp(r'^\s*([^:]{1,60}):\s*$').firstMatch(line) : null;

  final title = bracket?.group(1) ?? colon?.group(1);
  if (title == null) return null;

  final kind = _kindOf(title);
  if (bracket == null && kind == SectionKind.unknown) return null;
  return (title: title.trim(), source: line, kind: kind);
}

const Map<SectionKind, List<String>> _kindKeywords = {
  SectionKind.verse: ['куплет', 'verse'],
  SectionKind.chorus: ['припев', 'chorus', 'refrain'],
  SectionKind.bridge: ['бридж', 'мост', 'bridge'],
  SectionKind.intro: ['вступление', 'интро', 'intro'],
  SectionKind.outro: ['концовка', 'кода', 'outro', 'coda'],
  SectionKind.solo: ['соло', 'проигрыш', 'solo', 'interlude', 'instrumental'],
};

SectionKind _kindOf(String title) {
  final t = title.toLowerCase();
  for (final e in _kindKeywords.entries) {
    if (e.value.any((k) => t.contains(k))) return e.key;
  }
  return SectionKind.unknown;
}

List<Line> _parseLines(List<String> lines) {
  final result = <Line>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final nextIsLyric =
        i + 1 < lines.length && _isLyricLine(lines[i + 1]);
    if (isTabLineText(line)) {
      result.add(Line([RawToken(line)], source: line));
    } else if (isChordLineText(line) && nextIsLyric) {
      result.add(_mergePair(line, lines[i + 1]));
      i++;
    } else if (isChordLineText(line)) {
      result.add(_progressionLine(line));
    } else {
      result.add(_lyricLine(line));
    }
  }
  return result;
}

bool _isLyricLine(String line) =>
    !isTabLineText(line) && !isChordLineText(line);

Line _lyricLine(String line) {
  final split = _splitAnnotation(line, _isWordTokenText);
  final head = split?.head ?? line;
  final tokens = <Token>[
    for (final m in RegExp(r'\S+').allMatches(head)) WordToken(m[0]!),
  ];
  if (split != null) {
    tokens.add(AnnotationToken(split.annotation));
  }
  return Line(tokens, source: line);
}

Line _progressionLine(String line) {
  final split = _splitAnnotation(line, _isChordTokenText);
  final head = split?.head ?? line;
  final tokens = <Token>[];
  final pieces = scanChordLine(head);
  for (var i = 0; i < pieces.length; i++) {
    final p = pieces[i];
    if (p is ChordPiece) {
      tokens.add(ChordToken(p.chord));
      continue;
    }
    final text = (p as GapPiece).text.trim();
    if (text.isEmpty) continue;
    final hasChordAfter = pieces.skip(i + 1).any((x) => x is ChordPiece);
    tokens.add(InlineToken(text, endOfLine: !hasChordAfter));
  }
  if (split != null) {
    tokens.add(InlineToken(split.annotation, endOfLine: true));
  }
  return Line(tokens, source: line);
}

/// Склеивает пару физических строк в одну [Line].
///
/// Аккорд привязывается к слову, только если их колонки пересекаются;
/// аккорд над пробелом между словами становится отдельным пустым словом
/// [WordToken] с этим аккордом. Первый аккорд слова — поле [WordToken.chord],
/// следующие — токенами сразу после слова; аккорд правее конца последнего
/// слова — токеном конца строки. Хвосты-аннотации — [InlineToken]/[AnnotationToken].
Line _mergePair(String over, String under) {
  final overSplit = _splitAnnotation(over, _isChordTokenText);
  final underSplit = _splitAnnotation(under, _isWordTokenText);
  final chordPart = overSplit?.head ?? over;
  final wordPart = underSplit?.head ?? under;

  final wordMatches = RegExp(r'\S+').allMatches(wordPart).toList();
  final pieces = scanChordLine(chordPart);

  final slotText = <String>[];
  final slotStart = <int>[];
  final slotChord = <Chord?>[];
  final slotExtras = <List<Token>>[];
  for (final m in wordMatches) {
    slotText.add(m[0]!);
    slotStart.add(m.start);
    slotChord.add(null);
    slotExtras.add(<Token>[]);
  }

  final lastWordEnd = wordMatches.last.start + wordMatches.last[0]!.length;
  final lineEnd = <Token>[];
  var lastChordSlot = -1;

  int chordSlot(ChordPiece p) {
    for (var i = 0; i < slotText.length; i++) {
      if (slotText[i].isEmpty) continue;
      final wordEnd = slotStart[i] + slotText[i].length;
      if (p.start < wordEnd && p.end > slotStart[i]) return i;
    }
    return -1;
  }

  int insertEmptySlot(int column) {
    var i = 0;
    while (i < slotStart.length && slotStart[i] < column) {
      i++;
    }
    slotStart.insert(i, column);
    slotText.insert(i, '');
    slotChord.insert(i, null);
    slotExtras.insert(i, <Token>[]);
    return i;
  }

  for (final p in pieces) {
    if (p is GapPiece) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      final hasChordAfter =
          pieces.any((x) => x is ChordPiece && x.start >= p.end);
      if (hasChordAfter) {
        if (lastChordSlot >= 0) {
          slotExtras[lastChordSlot].add(InlineToken(text));
        }
      } else {
        lineEnd.add(InlineToken(text, endOfLine: true));
      }
      continue;
    }

    final chord = p as ChordPiece;
    final slot = chordSlot(chord);
    if (slot == -1) {
      if (chord.start >= lastWordEnd) {
        lineEnd.add(ChordToken(chord.chord, endOfLine: true));
        lastChordSlot = -1;
      } else {
        final s = insertEmptySlot(chord.start);
        slotChord[s] = chord.chord;
        lastChordSlot = s;
      }
    } else if (slotChord[slot] == null) {
      slotChord[slot] = chord.chord;
      lastChordSlot = slot;
    } else {
      slotExtras[slot].add(ChordToken(chord.chord));
      lastChordSlot = slot;
    }
  }

  final tokens = <Token>[];
  for (var i = 0; i < slotText.length; i++) {
    tokens.add(WordToken(slotText[i], chord: slotChord[i]));
    tokens.addAll(slotExtras[i]);
  }
  tokens.addAll(lineEnd);
  if (overSplit != null) {
    tokens.add(InlineToken(overSplit.annotation, endOfLine: true));
  }
  if (underSplit != null) {
    tokens.add(AnnotationToken(underSplit.annotation));
  }
  return Line(tokens, source: '$over\n$under');
}

/// Кусок аккордной строки: аккорд или не-аккордный текст между ними.
sealed class ChordLinePiece {
  const ChordLinePiece(this.start, this.end);

  final int start;
  final int end;
}

class ChordPiece extends ChordLinePiece {
  const ChordPiece(this.chord, super.start, super.end);

  final Chord chord;
}

class GapPiece extends ChordLinePiece {
  const GapPiece(this.text, super.start, super.end);

  final String text;
}

/// Сканирует строку аккордов без анкоров: каждый аккорд — [ChordPiece],
/// текст между ними (включая пробелы) — [GapPiece]. Куски покрывают строку
/// целиком, позиции считаются по нормализованной (латиница) строке.
List<ChordLinePiece> scanChordLine(String line) {
  final normalized = _normalizeLookalikes(line);
  final pieces = <ChordLinePiece>[];
  var cursor = 0;
  for (final m in _chordRe.allMatches(normalized)) {
    if (m.start > cursor) {
      pieces.add(GapPiece(line.substring(cursor, m.start), cursor, m.start));
    }
    pieces.add(ChordPiece(_chordFromMatch(m), m.start, m.end));
    cursor = m.end;
  }
  if (cursor < line.length) {
    pieces.add(GapPiece(line.substring(cursor), cursor, line.length));
  }
  return pieces;
}

// ---------------------------------------------------------------------------
// Рендеринг
// ---------------------------------------------------------------------------

/// Собирает текст песни: секции через одну пустую строку, файл завершается
/// переводом строки.
///
/// [fromSource] — использовать исходные строки как есть (байт-в-байт для
/// нетронутого); при `false` всё пересобирается из токенов по правилам
/// макета — «канонический» вид.
String renderSong(ParsedSong song, {bool fromSource = true}) {
  final parts = song.sections
      .map((s) => _renderSection(s, fromSource))
      .where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '';
  return '${parts.join('\n\n')}\n';
}

String _renderSection(Section section, bool fromSource) {
  final header = fromSource
      ? (section.titleSource ??
          (section.title == null ? null : '[${section.title}]'))
      : (section.title == null ? null : '[${section.title}]');
  final out = <String?>[header];
  out.addAll(section.lines.map((l) => _renderLine(l, fromSource)));
  return out.whereType<String>().join('\n');
}

String _renderLine(Line line, bool fromSource) {
  if (fromSource && line.source != null) return line.source!;
  if (line.tokens.length == 1 && line.tokens.single is RawToken) {
    return (line.tokens.single as RawToken).text;
  }
  if (line.isProgression) {
    return _renderProgression(line.tokens);
  }
  return _renderMerged(line.tokens);
}

/// Прогрессия: аккорды через три пробела, inline-куски («~») — вплотную,
/// хвостовая аннотация — через один пробел в конце.
String _renderProgression(List<Token> tokens) {
  final out = StringBuffer();
  var prevInline = false;
  for (final t in tokens) {
    switch (t) {
      case ChordToken(:final chord):
        if (out.isNotEmpty && !prevInline) out.write('   ');
        out.write(chord.display);
        prevInline = false;
      case InlineToken(:final text, :final endOfLine):
        if (endOfLine && out.isNotEmpty) out.write(' ');
        out.write(text);
        prevInline = !endOfLine;
      case RawToken(:final text):
        if (out.isNotEmpty && !prevInline) out.write('   ');
        out.write(text);
        prevInline = false;
      case AnnotationToken(:final text):
        out.write(' $text');
        prevInline = false;
      case WordToken():
        break;
    }
  }
  return out.toString();
}

/// Пересборка слитной строки единым проходом слева направо: слово и его
/// первый аккорд встают в одну колонку, доп. аккорды и висячие аккорды
/// расталкивают зазор, аккорды конца строки — за последним словом.
String _renderMerged(List<Token> tokens) {
  final chords = StringBuffer();
  final words = StringBuffer();
  final wordAnnots = <String>[];
  var prevInline = false;

  int mx(int a, int b) => a > b ? a : b;

  for (final t in tokens) {
    switch (t) {
      case WordToken(:final text, :final chord):
        final s = (words.isEmpty && chords.isEmpty)
            ? 0
            : mx(words.length + 1, chords.length + 1);
        words.write(' ' * (s - words.length) + text);
        if (chord != null) {
          chords.write(' ' * (s - chords.length) + chord.display);
        }
        prevInline = false;
      case ChordToken(:final chord, :final endOfLine):
        if (endOfLine) {
          final s = mx(words.length + 1, chords.length + 1);
          chords.write(' ' * (s - chords.length) + chord.display);
        } else {
          final s = prevInline
              ? chords.length
              : (chords.isEmpty ? 0 : chords.length + 1);
          chords.write(' ' * (s - chords.length) + chord.display);
        }
        prevInline = false;
      case InlineToken(:final text, :final endOfLine):
        if (endOfLine) {
          final s = mx(words.length + 1, chords.length + 1);
          chords.write(' ' * (s - chords.length) + text);
          prevInline = false;
        } else {
          chords.write(text);
          prevInline = true;
        }
      case RawToken(:final text):
        final s = prevInline
            ? chords.length
            : (chords.isEmpty ? 0 : chords.length + 1);
        chords.write(' ' * (s - chords.length) + text);
        prevInline = false;
      case AnnotationToken(:final text):
        wordAnnots.add(text);
        prevInline = false;
    }
  }

  words.write(wordAnnots.map((a) => ' $a').join());
  return chords.isEmpty ? words.toString() : '$chords\n$words';
}

// ---------------------------------------------------------------------------
// Общие распознаватели (используются и транспозером)
// ---------------------------------------------------------------------------

/// Полный аккорд: тоника + качество (+ слэш-бас). Без анкоров — чтобы
/// [scanChordLine] находил аккорды и внутри слипшихся кусков («G#7~A7»);
/// [parseChord] сам проверяет совпадение по всей длине токена.
final RegExp _chordRe = RegExp(
  r'([A-G])([#b♯♭]?)'
  r'((?:maj|min|sus|dim|aug|add|alt|mM|m|M|°|º|ø|Δ|\+|-|#|b|\d|\(|\))*)'
  r'(?:/([A-G])([#b♯♭]?))?',
);

/// Кириллические буквы-двойники латинских — в аккордах из-за не
/// переключённой раскладки («С7» вместо «C7»). Индексы строк синхронны.
const String _lookalikeCyrillic = 'АВЕКМНОРСТУХ';
const String _lookalikeLatin = 'ABEKMHOPCTYX';

final RegExp _lookalikeRe = RegExp('[АВЕКМНОРСТУХ]');

String _normalizeLookalikes(String token) {
  if (!_lookalikeRe.hasMatch(token)) return token;
  return String.fromCharCodes(token.runes.map((r) {
    final i = _lookalikeCyrillic.indexOf(String.fromCharCode(r));
    return i == -1 ? r : _lookalikeLatin.codeUnitAt(i);
  }));
}

/// Разбирает токен как аккорд; null — если это не аккорд. Кириллические
/// двойники нормализуются в латиницу. Токен должен совпасть целиком.
Chord? parseChord(String token) {
  final normalized = _normalizeLookalikes(token);
  final m = _chordRe.firstMatch(normalized);
  if (m == null || m.start != 0 || m.end != normalized.length) return null;
  return _chordFromMatch(m);
}

Chord _chordFromMatch(Match m) => Chord(
      root: m[1]! + (m[2] ?? ''),
      quality: m[3] ?? '',
      bass: m[4] == null ? null : m[4]! + (m[5] ?? ''),
    );

final RegExp _tabLineStart = RegExp(r'^(e|B|G|D|A|E)\s*\|');

bool isTabLineText(String line) {
  final t = line.trimLeft();
  return _tabLineStart.hasMatch(t) || t.startsWith('----');
}

final RegExp _symbolStart = RegExp(r'^[^\p{L}\p{N}]', unicode: true);

bool _isWordTokenText(String token) => !_symbolStart.hasMatch(token);

bool _isChordTokenText(String token) => parseChord(token) != null;

/// Делит строку на ведущую часть и хвост-аннотацию: хвост начинается с
/// первого токена, стартующего с «символа» (не буква и не цифра: «//», «(»,
/// «*»…), ведущая часть должна быть непустой и целиком подходить под
/// [isLeading]. null — эвристика не сработала.
({String head, String annotation})? _splitAnnotation(
    String line, bool Function(String token) isLeading) {
  final tokens = RegExp(r'\S+').allMatches(line).toList();
  if (tokens.isEmpty) return null;
  var i = 0;
  while (i < tokens.length && isLeading(tokens[i][0]!)) {
    i++;
  }
  if (i == 0 || i == tokens.length) return null;
  if (!_symbolStart.hasMatch(tokens[i][0]!)) return null;
  return (
    head: line.substring(0, tokens[i].start),
    annotation: line.substring(tokens[i].start),
  );
}

/// Строка считается строкой аккордов, когда аккорды покрывают больше половины
/// не-пробельных символов (заголовки вида «[Куплет 1]» не считаются) — иначе
/// текст песни с редкими «Am»/«A» не отличить. Строка с аккордами и
/// хвостом-аннотацией («G C // комментарий») аккордная без всякого
/// большинства.
bool isChordLineText(String line) {
  if (_splitAnnotation(line, _isChordTokenText) != null) return true;
  final body = line.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  var chordChars = 0;
  for (final p in scanChordLine(body)) {
    if (p is ChordPiece) chordChars += p.end - p.start;
  }
  final nonWs = body.replaceAll(RegExp(r'\s'), '').length;
  return nonWs > 0 && chordChars * 2 > nonWs;
}
