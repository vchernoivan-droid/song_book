import 'song_parser.dart';

class LyricLocator {
  static const defaultTailWords = 8;
  static const defaultMinScore = 0.4;
  static const substitutionCost = 1.15;
  static const gapCost = 1.0;
  static const bandBackLines = 2;
  static const bandForwardLines = 4;
  static const wordExactShare = 0.8;
  static const minExtendingWordLength = 2;

  static const _epsilon = 1e-9;

  final String _chars;
  final List<int> _charLines;
  final int _lineCount;

  factory LyricLocator(ParsedSong song) {
    final buf = StringBuffer();
    final lines = <int>[];
    var count = 0;
    for (final section in song.sections) {
      if (section.lines.isEmpty && section.title == null) continue;
      for (final line in section.lines) {
        for (final w in _wordsOfLine(line)) {
          lines.addAll(List<int>.filled(w.length, count));
          buf.write(w);
        }
        count++;
      }
    }
    return LyricLocator._(buf.toString(), lines, count);
  }

  LyricLocator._(this._chars, this._charLines, this._lineCount);

  int get lineCount => _lineCount;

  int? locate(
    List<String> recognized, {
    int? previousLine,
    int tailWords = defaultTailWords,
    double minScore = defaultMinScore,
  }) {
    if (recognized.isEmpty || _chars.isEmpty) return null;
    final tail = recognized.length <= tailWords
        ? recognized
        : recognized.sublist(recognized.length - tailWords);
    final t = tail.join();
    if (t.isEmpty) return null;

    var a = 0;
    var b = _chars.length;
    if (previousLine != null) {
      final first = _charLines.indexWhere((l) => l >= previousLine - bandBackLines);
      if (first < 0) return null;
      final last = _charLines.indexWhere((l) => l > previousLine + bandForwardLines);
      a = first;
      if (last >= 0) b = last;
    }
    final sub = _chars.substring(a, b);
    final n = t.length;
    final m = sub.length;
    if (m == 0) return null;

    final dp = List.generate(
        n + 1, (_) => List<double>.filled(m + 1, 0, growable: false));
    for (var i = 1; i <= n; i++) {
      dp[i][0] = i * gapCost;
    }
    for (var i = 1; i <= n; i++) {
      final tc = t.codeUnitAt(i - 1);
      final row = dp[i];
      final prev = dp[i - 1];
      for (var j = 1; j <= m; j++) {
        final diag = prev[j - 1] +
            (tc == sub.codeUnitAt(j - 1) ? 0.0 : substitutionCost);
        var v = diag;
        final byTailGap = prev[j] + gapCost;
        if (byTailGap < v) v = byTailGap;
        final bySongGap = row[j - 1] + gapCost;
        if (bySongGap < v) v = bySongGap;
        row[j] = v;
      }
    }

    var jStar = 0;
    var bestCost = dp[n][0];
    for (var j = 1; j <= m; j++) {
      if (dp[n][j] < bestCost) {
        bestCost = dp[n][j];
        jStar = j;
      }
    }
    if (1 - bestCost / n < minScore) return null;

    final aligned = List<int?>.filled(n, null);
    final exact = List<bool>.filled(n, false);
    var i = n;
    var j = jStar;
    while (i > 0 && j > 0) {
      final c = t.codeUnitAt(i - 1) == sub.codeUnitAt(j - 1)
          ? 0.0
          : substitutionCost;
      if ((dp[i][j] - (dp[i - 1][j - 1] + c)).abs() < _epsilon) {
        aligned[i - 1] = j - 1;
        exact[i - 1] = c == 0;
        i--;
        j--;
      } else if ((dp[i][j] - (dp[i - 1][j] + gapCost)).abs() < _epsilon) {
        i--;
      } else if ((dp[i][j] - (dp[i][j - 1] + gapCost)).abs() < _epsilon) {
        j--;
      } else {
        break;
      }
    }

    final starts = List<int>.filled(tail.length, 0);
    for (var w = 1; w < tail.length; w++) {
      starts[w] = starts[w - 1] + tail[w - 1].length;
    }
    for (var w = tail.length; w-- > 0;) {
      final from = starts[w];
      final to = from + tail[w].length;
      if (to - from < minExtendingWordLength) continue;
      int? wordEnd;
      var exactCount = 0;
      for (var k = from; k < to; k++) {
        final at = aligned[k];
        if (at != null) wordEnd = at;
        if (exact[k]) exactCount++;
      }
      if (wordEnd != null && exactCount >= wordExactShare * (to - from)) {
        return _charLines[a + wordEnd];
      }
    }
    return null;
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

  static List<String> _wordsOfLine(Line line) {
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
}
