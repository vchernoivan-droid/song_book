import 'package:flutter/painting.dart';

import 'song_parser.dart';

const songHeaderColor = Color(0xFF2E7D32);
const songChordColor = Color(0xFF1565C0);

List<InlineSpan> songHighlightSpans(
  String text, {
  required Color headerColor,
  required Color chordColor,
}) {
  final spans = <InlineSpan>[];

  void plain(String s) {
    if (s.isNotEmpty) spans.add(TextSpan(text: s));
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final startsBlock = i == 0 || lines[i - 1].trim().isEmpty;
    if (line.isNotEmpty) {
      if (startsBlock && isSectionHeaderText(line)) {
        spans.add(TextSpan(text: line, style: TextStyle(color: headerColor)));
      } else if (isChordLineText(line)) {
        var cursor = 0;
        for (final l in lexLine(line)) {
          if (l is! ChordLex) continue;
          plain(line.substring(cursor, l.start));
          spans.add(TextSpan(
            text: line.substring(l.start, l.end),
            style: TextStyle(color: chordColor),
          ));
          cursor = l.end;
        }
        plain(line.substring(cursor));
      } else {
        plain(line);
      }
    }
    if (i < lines.length - 1) plain('\n');
  }
  return spans;
}
