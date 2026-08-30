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
  final String text;

  /// Хвост аккордной строки (true) или строки текста (false) — рендерится
  /// в конце своей физической строки.
  final bool chordLine;

  const AnnotationToken(this.text, {required this.chordLine});

  @override
  bool operator ==(Object other) =>
      other is AnnotationToken &&
      other.text == text &&
      other.chordLine == chordLine;

  @override
  int get hashCode => Object.hash(text, chordLine);
}

/// Строка песни. Слитная пара «аккорды + текст» — одна [Line]: первый
/// аккорд слова — в поле [WordToken.chord], дополнительные смены на слове —
/// [ChordToken] сразу после него, аккорды за концом слов — в конце списка
/// с [ChordToken.endOfLine].
class Line {
  final List<Token> tokens;
  final String? source;

  const Line(this.tokens, {this.source});

  /// Строка только из аккордов (интро, проигрыш без текста).
  bool get isProgression =>
      tokens.isNotEmpty && tokens.every((t) => t is ChordToken);
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
    tokens.add(AnnotationToken(split.annotation, chordLine: false));
  }
  return Line(tokens, source: line);
}

Line _progressionLine(String line) {
  final split = _splitAnnotation(line, _isChordTokenText);
  final head = split?.head ?? line;
  final tokens = RegExp(r'\S+').allMatches(head).map(_overToken).toList();
  if (split != null) {
    tokens.add(AnnotationToken(split.annotation, chordLine: true));
  }
  return Line(tokens, source: line);
}

/// Склеивает пару физических строк в одну [Line].
///
/// Аккорд относится к последнему слову, начинающемуся не позже его колонки
/// (округление назад — в разборах из интернета аккорды обычно «уехавшие»
/// вправо, а не влево); аккорд левее первого слова — к первому слову.
/// Первый аккорд слова становится полем [WordToken.chord], следующие —
/// токенами сразу после слова; аккорд правее конца последнего слова —
/// токеном конца строки. Хвосты-аннотации обеих строк — [AnnotationToken].
Line _mergePair(String over, String under) {
  final overSplit = _splitAnnotation(over, _isChordTokenText);
  final underSplit = _splitAnnotation(under, _isWordTokenText);
  final chordPart = overSplit?.head ?? over;
  final wordPart = underSplit?.head ?? under;

  final overs = RegExp(r'\S+').allMatches(chordPart).toList();
  final words = RegExp(r'\S+').allMatches(wordPart).toList();

  final bound = <int>[];
  for (final o in overs) {
    var w = 0;
    while (w + 1 < words.length && words[w + 1].start <= o.start) {
      w++;
    }
    bound.add(w);
  }

  final lastWordEnd = words.last.start + words.last[0]!.length;
  final wordChords = List<Chord?>.filled(words.length, null);
  final extras = List.generate(words.length, (_) => <Token>[]);
  final lineEnd = <Token>[];

  for (var i = 0; i < overs.length; i++) {
    final token = _overToken(overs[i]);
    final w = bound[i];
    final beyondWords = w == words.length - 1 && overs[i].start >= lastWordEnd;
    if (beyondWords && token is ChordToken) {
      lineEnd.add(ChordToken(token.chord, endOfLine: true));
    } else if (token is ChordToken && wordChords[w] == null) {
      wordChords[w] = token.chord;
    } else {
      extras[w].add(token);
    }
  }

  final tokens = <Token>[];
  for (var w = 0; w < words.length; w++) {
    tokens.add(WordToken(words[w][0]!, chord: wordChords[w]));
    tokens.addAll(extras[w]);
  }
  tokens.addAll(lineEnd);
  if (overSplit != null) {
    tokens.add(AnnotationToken(overSplit.annotation, chordLine: true));
  }
  if (underSplit != null) {
    tokens.add(AnnotationToken(underSplit.annotation, chordLine: false));
  }
  return Line(tokens, source: '$over\n$under');
}

Token _overToken(RegExpMatch m) {
  final chord = parseChord(m[0]!);
  return chord == null ? RawToken(m[0]!) : ChordToken(chord);
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
    return line.tokens
        .map((t) => (t as ChordToken).chord.display)
        .join('   ');
  }
  return _renderMerged(line.tokens);
}

/// Пересборка слитной строки: аккорд слова — над его началом, доп. смены —
/// рядом с коллизионным сдвигом, аккорды конца строки — за последним словом,
/// аннотации — в конце своей физической строки.
String _renderMerged(List<Token> tokens) {
  final words = <String>[];
  final blocks = <({int word, String text, bool endOfLine})>[];
  final chordAnnots = <String>[];
  final wordAnnots = <String>[];
  for (final t in tokens) {
    switch (t) {
      case WordToken(:final text, :final chord):
        words.add(text);
        if (chord != null) {
          blocks.add((
              word: words.length - 1, text: chord.display, endOfLine: false));
        }
      case ChordToken(:final chord, :final endOfLine):
        blocks.add((
          word: words.isEmpty ? 0 : words.length - 1,
          text: chord.display,
          endOfLine: endOfLine,
        ));
      case RawToken(:final text):
        blocks.add((
          word: words.isEmpty ? 0 : words.length - 1,
          text: text,
          endOfLine: false,
        ));
      case AnnotationToken(:final text, :final chordLine):
        if (chordLine && words.isNotEmpty) {
          blocks.add((
            word: words.length - 1,
            text: text,
            endOfLine: true,
          ));
        } else if (chordLine) {
          chordAnnots.add(text);
        } else {
          wordAnnots.add(text);
        }
    }
  }
  if (words.isEmpty) {
    return blocks.map((b) => b.text).join('   ') +
        chordAnnots.map((a) => ' $a').join();
  }

  final wordStarts = <int>[];
  var col = 0;
  for (final w in words) {
    wordStarts.add(col);
    col += w.length + 1;
  }
  final afterLastWord = wordStarts.last + words.last.length + 1;

  var chordLine = '';
  for (final b in blocks) {
    var start = b.endOfLine ? afterLastWord : wordStarts[b.word];
    if (chordLine.isNotEmpty && start <= chordLine.length) {
      start = chordLine.length + 1;
    }
    chordLine += ' ' * (start - chordLine.length) + b.text;
  }

  var wordLine = words.join(' ');
  wordLine += wordAnnots.map((a) => ' $a').join();
  return chordLine.isEmpty ? wordLine : '$chordLine\n$wordLine';
}

// ---------------------------------------------------------------------------
// Общие распознаватели (используются и транспозером)
// ---------------------------------------------------------------------------

/// Полный аккорд: тоника + качество (+ слэш-бас).
final RegExp _chordRe = RegExp(
  r'^([A-G])([#b♯♭]?)'
  r'((?:maj|min|sus|dim|aug|add|alt|mM|m|M|°|º|ø|Δ|\+|-|#|b|\d|\(|\))*)'
  r'(?:/([A-G])([#b♯♭]?))?$',
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
/// двойники нормализуются в латиницу.
Chord? parseChord(String token) {
  final m = _chordRe.firstMatch(_normalizeLookalikes(token));
  if (m == null) return null;
  return Chord(
    root: m[1]! + (m[2] ?? ''),
    quality: m[3] ?? '',
    bass: m[4] == null ? null : m[4]! + (m[5] ?? ''),
  );
}

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

/// Строка считается строкой аккордов, когда аккордов строго больше половины
/// «слов» (служебные заголовки вида «[Куплет 1]» не считаются словами) —
/// иначе текст песни с редкими «Am»/«A» не отличить. Строка с аккордами и
/// хвостом-аннотацией («G C // комментарий») аккордная без всякого
/// большинства.
bool isChordLineText(String line) {
  if (_splitAnnotation(line, _isChordTokenText) != null) return true;
  final withoutHeaders = line.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  var chords = 0;
  var total = 0;
  for (final token in withoutHeaders.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    total++;
    if (parseChord(token) != null) chords++;
  }
  return total > 0 && chords * 2 > total;
}
