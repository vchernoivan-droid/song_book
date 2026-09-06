// Держим верх активной строки на fraction высоты экрана; ниже 0 не уходим.
double targetOffset({
  required double lineTop,
  required double viewport,
  double fraction = 0.4,
  double topPadding = 16,
}) {
  final t = lineTop + topPadding - viewport * fraction;
  return t < 0 ? 0 : t;
}

// Верх логической строки: номер её физической строки × lineHeight.
List<double> lineTops({
  required String text,
  required List<({int start, int end})> ranges,
  required double lineHeight,
}) {
  final newlines = List<int>.filled(text.length + 1, 0);
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
    newlines[i + 1] = count;
  }
  return [for (final r in ranges) newlines[r.start] * lineHeight];
}
