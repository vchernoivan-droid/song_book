/// Переводит «строк в минуту» в скорость прокрутки (px/сек).
///
/// [tokenLines] — число токен-строк песни, [physicalLines] — число физических
/// строк канонического рендера. Их отношение — средняя высота одной
/// токен-строки, а [lineHeight] — высота одной физической строки в px.
double autoScrollPxPerSecond({
  required int linesPerMinute,
  required int tokenLines,
  required int physicalLines,
  required double lineHeight,
}) {
  if (tokenLines <= 0 || physicalLines <= 0) return 0;
  return linesPerMinute * (physicalLines / tokenLines) * lineHeight / 60;
}
