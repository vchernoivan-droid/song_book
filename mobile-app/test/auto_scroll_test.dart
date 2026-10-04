import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/auto_scroll.dart';

void main() {
  test('lineTops: y = номер физической строки × lineHeight', () {
    const text = 'A\nB\nC\n';
    const ranges = [
      (start: 0, end: 1),
      (start: 2, end: 3),
      (start: 4, end: 5),
    ];
    expect(lineTops(text: text, ranges: ranges, lineHeight: 10), [0, 10, 20]);
  });
}
