List<int> _newlinePrefix(String text) {
  final newlines = List<int>.filled(text.length + 1, 0);
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
    newlines[i + 1] = count;
  }
  return newlines;
}

List<double> lineTops({
  required String text,
  required List<({int start, int end})> ranges,
  required double lineHeight,
}) {
  final newlines = _newlinePrefix(text);
  return [for (final r in ranges) newlines[r.start] * lineHeight];
}

List<double> lineTextCenters({
  required String text,
  required List<({int start, int end})> ranges,
  required double lineHeight,
}) {
  final newlines = _newlinePrefix(text);
  return [
    for (final r in ranges) newlines[r.end] * lineHeight + lineHeight / 2,
  ];
}
