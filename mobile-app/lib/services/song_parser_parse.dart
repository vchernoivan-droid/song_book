part of 'song_parser.dart';

ParsedSong parseSong(String content) {
  final lines = content.split('\n');
  final first = _firstChord(lines);
  final tonic = first?.pitch ?? 0;

  final blocks = <List<String>>[];
  var block = <String>[];

  void flush() {
    if (block.isEmpty) return;
    blocks.add(block);
    block = <String>[];
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
    } else {
      block.add(line);
    }
  }
  flush();

  // Блок без заголовка — строфа предыдущей секции, не новая секция.
  final sections = <Section>[];
  for (final b in blocks) {
    final header = _parseHeader(b.first);
    final blockLines = _parseLines(header == null ? b : b.sublist(1), tonic);
    if (header == null && sections.isNotEmpty) {
      final prev = sections.last;
      sections[sections.length - 1] = Section(
        title: prev.title,
        kind: prev.kind,
        lines: [
          ...prev.lines,
          for (var i = 0; i < blockLines.length; i++)
            i == 0
                ? Line(blockLines[i].tokens, stanzaStart: true)
                : blockLines[i],
        ],
      );
    } else {
      sections.add(Section(
        title: header?.title,
        kind: header?.kind ?? SectionKind.unknown,
        lines: blockLines,
      ));
    }
  }
  return ParsedSong(sections,
      tonic: tonic, tonicName: first?.name ?? 'C');
}

({int pitch, String name})? _firstChord(List<String> lines) {
  for (final line in lines) {
    if (isTabLineText(line) || !isChordLineText(line)) continue;
    for (final l in lexLine(line)) {
      if (l is ChordLex) return (pitch: l.chord.root, name: l.rootName);
    }
  }
  return null;
}

// «[…]» всегда заголовок; «…:» — только если внутри ключевое слово.
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
  final split = _lyricSplit(line);
  final tokens = <Token>[
    for (final run in _runsOf(line, split.head)) ...wordSyllables(run.text),
  ];
  if (split.annotation != null) {
    tokens.add(AnnotationToken(split.annotation!));
  }
  return Line(tokens);
}

final RegExp _glueRe = RegExp(r'^~+$');

Line _progressionLine(String line, int tonic) {
  final tokens = <Token>[];
  int? gapStart;
  var gapEnd = 0;

  void flushGap() {
    if (gapStart != null) {
      final text = line.substring(gapStart!, gapEnd).trim();
      if (text.isNotEmpty) {
        tokens.add(InlineToken(text, glued: _glueRe.hasMatch(text)));
      }
    }
    gapStart = null;
  }

  for (final l in lexLine(line, skipPeriods: true)) {
    if (l is ChordLex) {
      flushGap();
      tokens.add(ChordToken(Chord.fromPitch(l.chord, tonic)));
    } else {
      gapStart ??= l.start;
      gapEnd = l.end;
    }
  }
  flushGap();
  return Line(tokens);
}

Line _mergePair(String over, String under, int tonic) {
  final underSplit = _lyricSplit(under);
  final wordRuns = _runsOf(under, underSplit.head);
  final lex = lexLine(over, skipPeriods: true);

  final slotText = <String>[];
  final slotStart = <int>[];
  final slotEnd = <int>[];
  final slotDash = <SyllableDash>[];
  final slotChord = <Chord?>[];
  final slotExtras = <List<Token>>[];
  for (final run in wordRuns) {
    for (final s in _wordSyllables(run.text, run.start)) {
      slotText.add(s.text);
      slotStart.add(s.start);
      slotEnd.add(s.end);
      slotDash.add(s.dash);
      slotChord.add(null);
      slotExtras.add(<Token>[]);
    }
  }

  final lastWordEnd = wordRuns.last.start + wordRuns.last.text.length;
  final lineEnd = <Token>[];
  var lastChordSlot = -1;
  var seenChord = false;
  int? gapStart;
  var gapEnd = 0;

  void flushGap() {
    if (gapStart == null) return;
    final text = over.substring(gapStart!, gapEnd).trim();
    gapStart = null;
    if (text.isEmpty || !seenChord) return;
    if (_glueRe.hasMatch(text)) {
      if (lastChordSlot >= 0) {
        slotExtras[lastChordSlot].add(InlineToken(text, glued: true));
      }
    } else {
      lineEnd.add(InlineToken(text));
    }
  }

  // Аккорд привязывается к слогу, если колонки пересекаются.
  int chordSlot(ChordLex l) {
    for (var i = 0; i < slotText.length; i++) {
      if (slotText[i].isEmpty) continue;
      if (l.start < slotEnd[i] && l.end > slotStart[i]) return i;
    }
    return -1;
  }

  // Аккорд над пробелом между словами → пустой слог.
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

  for (final l in lex) {
    if (l is! ChordLex) {
      gapStart ??= l.start;
      gapEnd = l.end;
      continue;
    }
    flushGap();
    seenChord = true;
    final slot = chordSlot(l);
    if (slot == -1) {
      if (l.start >= lastWordEnd) {
        lineEnd.add(
            ChordToken(Chord.fromPitch(l.chord, tonic), endOfLine: true));
        lastChordSlot = -1;
      } else {
        final s = insertEmptySlot(l.start);
        slotChord[s] = Chord.fromPitch(l.chord, tonic);
        lastChordSlot = s;
      }
    } else if (slotChord[slot] == null) {
      slotChord[slot] = Chord.fromPitch(l.chord, tonic);
      lastChordSlot = slot;
    } else {
      slotExtras[slot].add(ChordToken(Chord.fromPitch(l.chord, tonic)));
      lastChordSlot = slot;
    }
  }
  flushGap();

  final tokens = <Token>[];
  for (var i = 0; i < slotText.length; i++) {
    tokens.add(SyllableToken(slotText[i], dash: slotDash[i], chord: slotChord[i]));
    tokens.addAll(slotExtras[i]);
  }
  tokens.addAll(lineEnd);
  if (underSplit.annotation != null) {
    tokens.add(AnnotationToken(underSplit.annotation!));
  }
  return Line(tokens);
}

// Ведущий дефис входит в текст слога — колонки привязки совпадают с исходником.
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

// Без колонок и аккордов — для тестов.
List<SyllableToken> wordSyllables(String text) => [
      for (final s in _wordSyllables(text, 0))
        SyllableToken(s.text, dash: s.dash),
    ];
