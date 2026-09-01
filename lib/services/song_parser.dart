/// Парсер песни из «надстрочного» формата (аккорды строкой над текстом)
/// в структурную модель и рендер обратно.
///
/// Тоника — атрибут песни ([ParsedSong.tonic], при разборе — питч первого
/// аккорда), [Chord] хранит только смещения от неё: транспонирование —
/// смена тоники ([ParsedSong.transposed]), имена аккордов считаются
/// рендером через [Chord.display].
///
/// Модель: ParsedSong → Section[] → Line[] → Token[] (Syllable | Chord |
/// Raw | Annotation | Inline). Атом текста — слог ([SyllableToken]):
/// дефисные части исходника и слова без дефисов режутся на слоги
/// переносом (syllable_split); ведущий дефис части исходника входит в
/// текст слога и сохраняется при пересборке, новых дефисов пересборка
/// не добавляет — кроме стыков, растянутых раскладкой (см.
/// [_renderMerged]).
/// Пара физических строк «аккорды над текстом» склеивается в одну
/// [Line]: первый аккорд слога — поле
/// SyllableToken.chord (пересечение колонок), дополнительные смены на
/// слоге — ChordToken сразу после него, аккорды за концом слов —
/// ChordToken(endOfLine) в конце списка. Аккордная строка разбирается
/// целиком: хвостовые пометки («2x», «// можно C7») и «~»-переходы дают
/// плоские InlineToken/ChordToken — все аккорды песни модельные.
/// Хвосты текстовых строк («(2 раза)») — AnnotationToken. Колонки и
/// пробелы не хранятся: рендер всегда собирает строку заново:
/// внутри слова аккорды прижаты к слогам по печатной ширине, и когда имя
/// не влезает, стык растягивается дефисом; между словами за аккордами
/// без #/b резервируется колонка под знак — чтобы вёрстка не переезжала
/// при транспонировании.
library;

import 'syllable_split.dart';

/// Разновидность секции — по ключевым словам заголовка.
enum SectionKind { verse, chorus, bridge, intro, outro, solo, unknown }

const Map<String, int> _letterPitch = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

/// Предпочитаемые написания полутонов: диезы для C#, F#, бемоли для Eb, Ab, Bb.
const List<String> _pitchNames = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

int _mod12(int pitch) => ((pitch % 12) + 12) % 12;

/// Каноническое имя питча по таблице предпочтительных написаний.
String pitchName(int pitch) => _pitchNames[_mod12(pitch)];

/// Питч записанного корня: буква + случайный знак.
int _pitchOf(String root) {
  final letter = root.substring(0, 1);
  final accidental = root.length > 1 ? root.substring(1) : '';
  var pitch = _letterPitch[letter]!;
  if (accidental == '#' || accidental == '♯') pitch += 1;
  if (accidental == 'b' || accidental == '♭') pitch -= 1;
  return _mod12(pitch);
}

/// Абсолютный аккорд строкового слоя: питчи вместо имён. Используется
/// при сканировании текста ([scanChordLine], [parseChord]) и в строчной
/// замене аккордов редактора; модель получает [Chord] вычитанием тоники.
class PitchChord {
  final int root;
  final String quality;
  final int? bass;

  const PitchChord({required this.root, this.quality = '', this.bass});

  String get display => bass == null
      ? '${pitchName(root)}$quality'
      : '${pitchName(root)}$quality/${pitchName(bass!)}';

  @override
  bool operator ==(Object other) =>
      other is PitchChord &&
      other.root == root &&
      other.quality == quality &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(root, quality, bass);

  @override
  String toString() => display;
}

/// Аккорд модели: смещения от тоники песни, тоника не хранится —
/// имя появляется только в рендере ([display]).
class Chord {
  final int rootOffset;
  final String quality;
  final int? bassOffset;

  const Chord({
    required this.rootOffset,
    this.quality = '',
    this.bassOffset,
  });

  Chord.fromPitch(PitchChord chord, int tonic)
      : rootOffset = _mod12(chord.root - tonic),
        quality = chord.quality,
        bassOffset =
            chord.bass == null ? null : _mod12(chord.bass! - tonic);

  /// Имя аккорда в тональности [tonic]. Смещение 0 — тоника — рендерится
  /// написанным именем [tonicName], прочие — по таблице имён.
  String display(int tonic, [String? tonicName]) {
    String name(int offset) => offset == 0 && tonicName != null
        ? tonicName
        : pitchName(tonic + offset);
    final root = name(rootOffset);
    final bass =
        bassOffset == null ? null : name(bassOffset!);
    return bass == null ? '$root$quality' : '$root$quality/$bass';
  }

  @override
  bool operator ==(Object other) =>
      other is Chord &&
      other.rootOffset == rootOffset &&
      other.quality == quality &&
      other.bassOffset == bassOffset;

  @override
  int get hashCode => Object.hash(rootOffset, quality, bassOffset);

  @override
  String toString() => '$rootOffset$quality';
}

sealed class Token {
  const Token();
}

/// Позиция слога в слове: none — слово из одного слога, right — первый
/// слог, left — последний, both — середина. Начало слова — none|right.
enum SyllableDash { none, right, both, left }

class SyllableToken extends Token {
  /// Текст слога; может начинаться с дефиса исходника («-Мулла»),
  /// растяжка раскладки добавляет такой же, но нового не порождает
  /// в модели — он существует только в рендере.
  final String text;

  final SyllableDash dash;

  /// Первый аккорд слога (смена на его начале).
  final Chord? chord;

  const SyllableToken(this.text, {this.dash = SyllableDash.none, this.chord});

  @override
  bool operator ==(Object other) =>
      other is SyllableToken &&
      other.text == text &&
      other.dash == dash &&
      other.chord == chord;

  @override
  int get hashCode => Object.hash(text, dash, chord);
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
  bool operator ==(Object other) =>
      other is AnnotationToken && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class InlineToken extends Token {
  /// Не-аккордный кусок аккордной строки: «~»-наклейка между аккордами
  /// ([glued] — вплотную к предыдущему аккорду) или текстовая пометка
  /// («2x», «// комментарий») — через пробел.
  final String text;

  final bool glued;

  const InlineToken(this.text, {this.glued = false});

  @override
  bool operator ==(Object other) =>
      other is InlineToken && other.text == text && other.glued == glued;

  @override
  int get hashCode => Object.hash(text, glued);
}

/// Строка песни. Слитная пара «аккорды + текст» — одна [Line]: первый
/// аккорд слога — в поле [SyllableToken.chord], дополнительные смены на
/// слоге — [ChordToken] сразу после него, аккорды за концом слов — в
/// конце списка с [ChordToken.endOfLine].
class Line {
  final List<Token> tokens;

  const Line(this.tokens);

  /// Строка без слов (интро, проигрыш без текста): аккорды, inline-куски
  /// и хвостовые аннотации.
  bool get isProgression =>
      tokens.isNotEmpty && tokens.every((t) => t is! SyllableToken);
}

class Section {
  /// Распознанный текст заголовка («Куплет 1»); null — блока без заголовка.
  final String? title;

  final SectionKind kind;
  final List<Line> lines;

  const Section({
    this.title,
    this.kind = SectionKind.unknown,
    required this.lines,
  });
}

class ParsedSong {
  final List<Section> sections;

  /// Тоника песни (0–11): при разборе — питч первого аккорда.
  final int tonic;

  /// Написание тоники как в исходнике («G#», а не «Ab»): сам первый
  /// аккорд рендерится своим именем, остальные — по таблице имён.
  final String tonicName;

  const ParsedSong(this.sections, {this.tonic = 0, this.tonicName = 'C'});

  /// Транспонирование — смена тоники: смещения аккордов не меняются.
  ParsedSong transposed(int semitones) => semitones == 0
      ? this
      : ParsedSong(sections,
          tonic: _mod12(tonic + semitones),
          tonicName: pitchName(tonic + semitones));
}

// ---------------------------------------------------------------------------
// Парсинг
// ---------------------------------------------------------------------------

/// Разбирает текст песни (без служебной шапки транспонирования).
/// Тоника — первый аккорд (питч и написание); песня без аккордов
/// получает до-мажор.
ParsedSong parseSong(String content) {
  final lines = content.split('\n');
  final first = _firstChord(lines);

  final sections = <Section>[];
  final block = <String>[];

  void flush() {
    if (block.isEmpty) return;
    sections.add(_parseSection(block, first?.pitch ?? 0));
    block.clear();
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
    } else {
      block.add(line);
    }
  }
  flush();
  return ParsedSong(sections,
      tonic: first?.pitch ?? 0, tonicName: first?.name ?? 'C');
}

({int pitch, String name})? _firstChord(List<String> lines) {
  for (final line in lines) {
    if (isTabLineText(line) || !isChordLineText(line)) continue;
    final m = _chordRe.firstMatch(_normalizeLookalikes(line));
    if (m == null) continue;
    final root = m[1]! + (m[2] ?? '');
    return (pitch: _pitchOf(root), name: root);
  }
  return null;
}

Section _parseSection(List<String> block, int tonic) {
  final header = _parseHeader(block.first);
  final rest = header == null ? block : block.sublist(1);
  return Section(
    title: header?.title,
    kind: header?.kind ?? SectionKind.unknown,
    lines: _parseLines(rest, tonic),
  );
}

/// Распознаёт строку-заголовок: «[Куплет 1]» (всегда) или «Припев:»
/// (только если внутри есть ключевое слово секции).
({String title, SectionKind kind})? _parseHeader(String line) {
  final bracket = RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(line);
  final colon =
      bracket == null ? RegExp(r'^\s*([^:]{1,60}):\s*$').firstMatch(line) : null;

  final title = bracket?.group(1) ?? colon?.group(1);
  if (title == null) return null;

  final kind = _kindOf(title);
  if (bracket == null && kind == SectionKind.unknown) return null;
  return (title: title.trim(), kind: kind);
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

List<Line> _parseLines(List<String> lines, int tonic) {
  final result = <Line>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final nextIsLyric =
        i + 1 < lines.length && _isLyricLine(lines[i + 1]);
    if (isTabLineText(line)) {
      result.add(Line([RawToken(line)]));
    } else if (isChordLineText(line) && nextIsLyric) {
      result.add(_mergePair(line, lines[i + 1], tonic));
      i++;
    } else if (isChordLineText(line)) {
      result.add(_progressionLine(line, tonic));
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
    for (final m in RegExp(r'\S+').allMatches(head)) ...wordSyllables(m[0]!),
  ];
  if (split != null) {
    tokens.add(AnnotationToken(split.annotation));
  }
  return Line(tokens);
}

/// Наклейка-переход: кусок только из «~» прилипает к предыдущему аккорду.
final RegExp _glueRe = RegExp(r'^~+$');

Line _progressionLine(String line, int tonic) {
  final tokens = <Token>[];
  for (final p in scanChordLine(line)) {
    if (p is ChordPiece) {
      tokens.add(ChordToken(Chord.fromPitch(p.chord, tonic)));
      continue;
    }
    final text = (p as GapPiece).text.trim();
    if (text.isEmpty) continue;
    tokens.add(InlineToken(text, glued: _glueRe.hasMatch(text)));
  }
  return Line(tokens);
}

/// Склеивает пару физических строк в одну [Line].
///
/// Аккорд привязывается к слогу, только если их колонки пересекаются
/// (слог владеет хвостовым дефисом исходника); аккорд над пробелом между
/// словами становится отдельным пустым слогом. Первый аккорд слога —
/// поле [SyllableToken.chord], следующие — токенами сразу после слога;
/// аккорд правее конца последнего слова — токеном конца строки. Хвост
/// аккордной строки разбирается на плоские куски: аккорды — ChordToken,
/// текст — InlineToken. Хвост текстовой строки — [AnnotationToken].
Line _mergePair(String over, String under, int tonic) {
  final underSplit = _splitAnnotation(under, _isWordTokenText);
  final wordPart = underSplit?.head ?? under;

  final wordMatches = RegExp(r'\S+').allMatches(wordPart).toList();
  final pieces = scanChordLine(over);

  final slotText = <String>[];
  final slotStart = <int>[];
  final slotEnd = <int>[];
  final slotDash = <SyllableDash>[];
  final slotChord = <Chord?>[];
  final slotExtras = <List<Token>>[];
  for (final m in wordMatches) {
    for (final s in _wordSyllables(m[0]!, m.start)) {
      slotText.add(s.text);
      slotStart.add(s.start);
      slotEnd.add(s.end);
      slotDash.add(s.dash);
      slotChord.add(null);
      slotExtras.add(<Token>[]);
    }
  }

  final lastWordEnd = wordMatches.last.start + wordMatches.last[0]!.length;
  final lineEnd = <Token>[];
  var lastChordSlot = -1;
  var seenChord = false;

  int chordSlot(ChordPiece p) {
    for (var i = 0; i < slotText.length; i++) {
      if (slotText[i].isEmpty) continue;
      if (p.start < slotEnd[i] && p.end > slotStart[i]) return i;
    }
    return -1;
  }

  int insertEmptySlot(int column) {
    var i = 0;
    while (i < slotStart.length && slotStart[i] < column) {
      i++;
    }
    slotStart.insert(i, column);
    slotEnd.insert(i, column);
    slotText.insert(i, '');
    slotDash.insert(i, SyllableDash.none);
    slotChord.insert(i, null);
    slotExtras.insert(i, <Token>[]);
    return i;
  }

  for (final p in pieces) {
    if (p is GapPiece) {
      final text = p.text.trim();
      if (text.isEmpty || !seenChord) continue;
      if (_glueRe.hasMatch(text)) {
        if (lastChordSlot >= 0) {
          slotExtras[lastChordSlot].add(InlineToken(text, glued: true));
        }
      } else {
        lineEnd.add(InlineToken(text));
      }
      continue;
    }

    final chord = p as ChordPiece;
    seenChord = true;
    final slot = chordSlot(chord);
    if (slot == -1) {
      if (chord.start >= lastWordEnd) {
        lineEnd
            .add(ChordToken(Chord.fromPitch(chord.chord, tonic), endOfLine: true));
        lastChordSlot = -1;
      } else {
        final s = insertEmptySlot(chord.start);
        slotChord[s] = Chord.fromPitch(chord.chord, tonic);
        lastChordSlot = s;
      }
    } else if (slotChord[slot] == null) {
      slotChord[slot] = Chord.fromPitch(chord.chord, tonic);
      lastChordSlot = slot;
    } else {
      slotExtras[slot].add(ChordToken(Chord.fromPitch(chord.chord, tonic)));
      lastChordSlot = slot;
    }
  }

  final tokens = <Token>[];
  for (var i = 0; i < slotText.length; i++) {
    tokens.add(SyllableToken(slotText[i], dash: slotDash[i], chord: slotChord[i]));
    tokens.addAll(slotExtras[i]);
  }
  tokens.addAll(lineEnd);
  if (underSplit != null) {
    tokens.add(AnnotationToken(underSplit.annotation));
  }
  return Line(tokens);
}

/// Слоги слова, начинающегося в колонке [base]: части, разделённые
/// дефисами исходника, дополнительно режутся переносом. Ведущий дефис
/// части входит в текст и диапазон её первого слога — колонки привязки
/// совпадают с исходником. [SyllableToken.dash] — позиция в слове.
List<({String text, SyllableDash dash, int start, int end})>
    _wordSyllables(String word, int base) {
  final spans = <({String text, int start, int end})>[];

  final hyphenParts = word.contains('-') ? word.split('-') : null;
  if (hyphenParts != null && hyphenParts.every((p) => p.isEmpty)) {
    spans.add((text: word, start: 0, end: word.length));
  } else {
    final parts = hyphenParts ?? [word];
    var cursor = 0;
    for (var i = 0; i < parts.length; i++) {
      final syllables = splitWordToSyllables(parts[i]);
      for (var j = 0; j < syllables.length; j++) {
        final s = syllables[j];
        final text = i > 0 && j == 0 ? '-$s' : s;
        spans.add((text: text, start: cursor, end: cursor + text.length));
        cursor += text.length;
      }
    }
  }

  return [
    for (var i = 0; i < spans.length; i++)
      (
        text: spans[i].text,
        dash: spans.length == 1
            ? SyllableDash.none
            : i == 0
                ? SyllableDash.right
                : i == spans.length - 1
                    ? SyllableDash.left
                    : SyllableDash.both,
        start: base + spans[i].start,
        end: base + spans[i].end,
      ),
  ];
}

/// Слоги слова без привязки к колонкам и аккордам — для тестов и
/// последующего анализа структуры.
List<SyllableToken> wordSyllables(String text) => [
      for (final s in _wordSyllables(text, 0))
        SyllableToken(s.text, dash: s.dash),
    ];

/// Кусок аккордной строки: аккорд или не-аккордный текст между ними.
sealed class ChordLinePiece {
  const ChordLinePiece(this.start, this.end);

  final int start;
  final int end;
}

class ChordPiece extends ChordLinePiece {
  const ChordPiece(this.chord, super.start, super.end);

  final PitchChord chord;
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
/// переводом строки. Строки собираются из токенов по правилам макета —
/// «канонический» вид, имена аккордов — в тональности [ParsedSong.tonic].
String renderSong(ParsedSong song) {
  final parts = song.sections
      .map((s) => _renderSection(s, song.tonic, song.tonicName))
      .where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '';
  return '${parts.join('\n\n')}\n';
}

String _renderSection(Section section, int tonic, String tonicName) {
  final header = section.title == null ? null : '[${section.title}]';
  final out = <String?>[header];
  out.addAll(section.lines.map((l) => _renderLine(l, tonic, tonicName)));
  return out.whereType<String>().join('\n');
}

String _renderLine(Line line, int tonic, String tonicName) {
  if (line.tokens.length == 1 && line.tokens.single is RawToken) {
    return (line.tokens.single as RawToken).text;
  }
  if (line.isProgression) {
    return _renderProgression(line.tokens, tonic, tonicName);
  }
  return _renderMerged(line.tokens, tonic, tonicName);
}

/// Прогрессия: аккорды через три пробела, «~»-наклейки — вплотную,
/// текстовые пометки — через один пробел.
String _renderProgression(
    List<Token> tokens, int tonic, String tonicName) {
  final out = StringBuffer();
  var prevGlued = false;
  for (final t in tokens) {
    switch (t) {
      case ChordToken(:final chord):
        if (out.isNotEmpty) out.write(prevGlued ? '' : '   ');
        out.write(chord.display(tonic, tonicName));
        prevGlued = false;
      case InlineToken(:final text, :final glued):
        if (!glued && out.isNotEmpty) out.write(' ');
        out.write(text);
        prevGlued = glued;
      case RawToken(:final text):
        if (out.isNotEmpty && !prevGlued) out.write('   ');
        out.write(text);
        prevGlued = false;
      case AnnotationToken(:final text):
        out.write(' $text');
        prevGlued = false;
      case SyllableToken():
        break;
    }
  }
  return out.toString();
}

/// Эффективная ширина аккорда в колонках: имя плюс зарезервированное
/// место под случайный знак — у аккордов без #/b смена тоники может
/// его добавить. Одинакова для всех написаний одного аккорда, поэтому
/// вёрстка не переезжает при транспонировании.
int chordWidth(Chord chord, int tonic, [String? tonicName]) {
  final root = chord.rootOffset == 0 && tonicName != null
      ? tonicName
      : pitchName(chord.rootOffset + tonic);
  return chord.display(tonic, tonicName).length +
      (root.length == 1 ? 1 : 0);
}

/// Пересборка слитной строки единым проходом слева направо: слог и его
/// первый аккорд встают в одну колонку. Слоги одного слова пишутся
/// вплотную; когда имя аккорда не влезает в свой слог вплотную, слог
/// сдвигается вправо и стык получает дефис — слово растягивается ровно
/// настолько, насколько его растолкали аккорды. Между словами и в
/// хвосте строки действует резерв [chordWidth].
String _renderMerged(List<Token> tokens, int tonic, String tonicName) {
  final chords = StringBuffer();
  final words = StringBuffer();
  final wordAnnots = <String>[];
  var prevInline = false;
  var effEnd = -1;

  int mx(int a, int b) => a > b ? a : b;

  void writeChord(Chord chord, int col) {
    chords.write(
        ' ' * (col - chords.length) + chord.display(tonic, tonicName));
    effEnd = col + chordWidth(chord, tonic, tonicName);
  }

  for (final t in tokens) {
    switch (t) {
      case SyllableToken(:final text, :final dash, :final chord):
        final startsWord =
            dash == SyllableDash.none || dash == SyllableDash.right;
        if (startsWord) {
          final wordCol = (words.isEmpty && chords.isEmpty)
              ? 0
              : mx(words.length + 1, effEnd + 1);
          words.write(' ' * (wordCol - words.length) + text);
          if (chord != null) writeChord(chord, wordCol);
        } else if (chord == null) {
          words.write(text);
        } else {
          final hyphen = text.startsWith('-');
          final letters = words.length + (hyphen ? 1 : 0);
          // Внутри слова аккорды прижаты к слогу (фактический конец имени
          // + пробел); резерв действует только между словами.
          final col = mx(
              letters,
              prevInline ? effEnd : (chords.isEmpty ? 0 : chords.length + 1));
          words.write(col > letters
              ? '${' ' * (col - 1 - words.length)}${hyphen ? text : '-$text'}'
              : text);
          writeChord(chord, col);
        }
        prevInline = false;
      case ChordToken(:final chord, :final endOfLine):
        if (endOfLine) {
          writeChord(chord, mx(words.length + 1, effEnd + 1));
        } else {
          writeChord(chord, prevInline ? effEnd : effEnd + 1);
        }
        prevInline = false;
      case InlineToken(:final text, :final glued):
        if (glued) {
          // Наклейка пишется вплотную, а резерв ширины переносится за неё —
          // конец «A7~» и «Ab7~» занимает одинаковую полосу колонок.
          chords.write(text);
          effEnd += text.length;
        } else {
          final s = mx(words.length + 1, effEnd + 1);
          chords.write(' ' * (s - chords.length) + text);
          effEnd = chords.length;
        }
        prevInline = glued;
      case RawToken(:final text):
        final s = prevInline ? effEnd : effEnd + 1;
        chords.write(' ' * (s - chords.length) + text);
        prevInline = false;
        effEnd = chords.length;
      case AnnotationToken(:final text):
        wordAnnots.add(text);
        prevInline = false;
    }
  }

  words.write(wordAnnots.map((a) => ' $a').join());
  return chords.isEmpty ? words.toString() : '$chords\n$words';
}

// ---------------------------------------------------------------------------
// Общие распознаватели (используются и строчной заменой аккордов)
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
PitchChord? parseChord(String token) {
  final normalized = _normalizeLookalikes(token);
  final m = _chordRe.firstMatch(normalized);
  if (m == null || m.start != 0 || m.end != normalized.length) return null;
  return _chordFromMatch(m);
}

PitchChord _chordFromMatch(Match m) => PitchChord(
      root: _pitchOf(m[1]! + (m[2] ?? '')),
      quality: m[3] ?? '',
      bass: m[4] == null ? null : _pitchOf(m[4]! + (m[5] ?? '')),
    );

final RegExp _tabLineStart = RegExp(r'^(e|B|G|D|A|E)\s*\|');

bool isTabLineText(String line) {
  final t = line.trimLeft();
  return _tabLineStart.hasMatch(t) || t.startsWith('----');
}

final RegExp _symbolStart = RegExp(r'^[^\p{L}\p{N}]', unicode: true);

/// Одиночные дефисы и тире — пунктуация текста (разделитель частей
/// фразы), а не маркер хвоста-аннотации.
final RegExp _dashTokenRe = RegExp(r'^[-‒–—―−]+$');

bool _isWordTokenText(String token) => !_symbolStart.hasMatch(token);

bool _isChordTokenText(String token) => parseChord(token) != null;

/// Делит строку на ведущую часть и хвост-аннотацию: хвост начинается с
/// первого токена, стартующего с «символа» (не буква и не цифра: «//», «(»,
/// «*»…); одиночные тире текстом остаются. Ведущая часть должна быть
/// непустой и целиком подходить под [isLeading]. null — эвристика не
/// сработала.
({String head, String annotation})? _splitAnnotation(
    String line, bool Function(String token) isLeading) {
  final tokens = RegExp(r'\S+').allMatches(line).toList();
  if (tokens.isEmpty) return null;
  var i = 0;
  while (i < tokens.length &&
      (isLeading(tokens[i][0]!) || _dashTokenRe.hasMatch(tokens[i][0]!))) {
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
