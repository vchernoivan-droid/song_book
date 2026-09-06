part of 'song_parser.dart';

String renderSong(ParsedSong song) => renderSongLines(song).text;

// Канонический текст + char-диапазоны логических строк (для автоскролла).
({String text, List<({int start, int end})> lines}) renderSongLines(
    ParsedSong song) {
  final buf = StringBuffer();
  final ranges = <({int start, int end})>[];
  var written = 0;
  for (final section in song.sections) {
    if (section.lines.isEmpty && section.title == null) continue;
    if (written > 0) buf.write('\n');
    written++;
    if (section.title != null) {
      buf.write('[${section.title}]\n');
    }
    for (final line in section.lines) {
      final start = buf.length;
      buf.write(_renderLine(line, song.tonic, song.tonicName));
      final end = buf.length;
      ranges.add((start: start, end: end));
      buf.write('\n');
    }
  }
  return (text: buf.toString(), lines: ranges);
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

int chordWidth(Chord chord, int tonic, [String? tonicName]) {
  final root = chord.rootOffset == 0 && tonicName != null
      ? tonicName
      : pitchName(chord.rootOffset + tonic);
  return chord.display(tonic, tonicName).length +
      // компенсируем ширину #/b, чтобы строки не «ехали» при транспонировании
      (root.length == 1 ? 1 : 0);
}

String _renderMerged(List<Token> tokens, int tonic, String tonicName) {
  final chords = StringBuffer();
  final words = StringBuffer();
  final wordAnnots = <String>[];
  var prevInline = false;
  var effEnd = -1; // правая граница аккордной строки (с резервом под #/b)

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
          // Внутри слова — впритык, без резерва под #/b (он только между словами).
          final col = mx(
              letters,
              prevInline ? effEnd : (chords.isEmpty ? 0 : chords.length + 1));
          // Аккорд шире слога — слог съезжает вправо, стык растягивается дефисом.
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
          // Резерв ширины переносится за наклейку — «A7~» и «Ab7~» одинаково широки.
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
