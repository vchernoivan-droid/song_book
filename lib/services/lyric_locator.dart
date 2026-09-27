import 'song_parser.dart';

class LyricLocator {
  static const defaultWindowSize = 8;
  static const defaultMinScore = 0.4;
  static const defaultAnchor = 0.02;

  final List<String> _words = [];
  final List<int> _wordLines = [];
  int _lineCount = 0;

  LyricLocator(ParsedSong song) {
    for (final section in song.sections) {
      if (section.lines.isEmpty && section.title == null) continue;
      for (final line in section.lines) {
        final words = _wordsOfLine(line);
        for (final w in words) {
          _words.add(w);
          _wordLines.add(_lineCount);
        }
        _lineCount++;
      }
    }
  }

  int get lineCount => _lineCount;

  int? locate(
    List<String> recognized, {
    int? previousLine,
    int windowSize = defaultWindowSize,
    double minScore = defaultMinScore,
    double anchor = defaultAnchor,
  }) {
    if (recognized.isEmpty || _words.isEmpty) return null;
    final n = windowSize < recognized.length ? windowSize : recognized.length;
    final tail = recognized.sublist(recognized.length - n);

    var bestEff = -1.0;
    var bestRaw = -1.0;
    var bestLine = -1;
    for (var s = 0; s + n <= _words.length; s++) {
      var sum = 0.0;
      for (var k = 0; k < n; k++) {
        sum += _similarity(tail[k], _words[s + k]);
      }
      final raw = sum / n;
      final endLine = _wordLines[s + n - 1];
      final eff = previousLine == null
          ? raw
          : raw - anchor * (endLine - previousLine).abs();
      if (eff > bestEff) {
        bestEff = eff;
        bestRaw = raw;
        bestLine = endLine;
      }
    }
    return bestRaw >= minScore ? bestLine : null;
  }

  static List<String> keysOf(String text) {
    final keys = <String>[];
    for (final w in text.split(RegExp(r'\s+'))) {
      final key = phoneticKey(w);
      if (key.isNotEmpty) keys.add(key);
    }
    return keys;
  }

  static final RegExp _dropRe = RegExp(r'[^\p{L}\p{N}]', unicode: true);
  static const _devoicing = {
    'б': 'п',
    'в': 'ф',
    'г': 'к',
    'д': 'т',
    'ж': 'ш',
    'з': 'с',
  };

  static String phoneticKey(String text) {
    var s = text.toLowerCase().replaceAll('ё', 'е');
    s = s
        .replaceAll(_dropRe, '')
        .replaceAll('ь', '')
        .replaceAll('ъ', '')
        .replaceAll('о', 'а')
        .replaceAll('е', 'и');
    if (s.length > 1 && _devoicing.containsKey(s[s.length - 1])) {
      s = s.substring(0, s.length - 1) + _devoicing[s[s.length - 1]]!;
    }
    return _squeezeDoubles(s);
  }

  static String _squeezeDoubles(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i == 0 || s.codeUnitAt(i) != s.codeUnitAt(i - 1)) {
        buf.write(s[i]);
      }
    }
    return buf.toString();
  }

  List<String> _wordsOfLine(Line line) {
    final words = <String>[];
    var current = '';
    for (final token in line.tokens) {
      if (token is! SyllableToken) continue;
      final key = phoneticKey(token.text);
      if (key.isEmpty) continue;
      final startsWord =
          token.dash == SyllableDash.none || token.dash == SyllableDash.right;
      if (startsWord) {
        if (current.isNotEmpty) words.add(current);
        current = key;
      } else {
        current += key;
      }
    }
    if (current.isNotEmpty) words.add(current);
    return words;
  }

  double _similarity(String a, String b) {
    if (a == b) return 1;
    final m = a.length > b.length ? a.length : b.length;
    if (m == 0) return 1;
    return 1 - _levenshtein(a, b) / m;
  }

  int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        var v = prev[j + 1] + 1;
        final byInsert = cur[j] + 1;
        if (byInsert < v) v = byInsert;
        final bySub = prev[j] + cost;
        if (bySub < v) v = bySub;
        cur[j + 1] = v;
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }
}
