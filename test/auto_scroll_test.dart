import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/auto_scroll.dart';

void main() {
  test('строки/мин переводятся в px/сек', () {
    // 1 токен-строка = 1 физическая, lineHeight 13.5 → 10 строк/мин = 2.25 px/с.
    expect(
      autoScrollPxPerSecond(
        linesPerMinute: 10,
        tokenLines: 1,
        physicalLines: 1,
        lineHeight: 13.5,
      ),
      closeTo(2.25, 0.0001),
    );
  });

  test('пара аккорды+текст (2 физические на 1 токен-строку) удваивает высоту',
      () {
    expect(
      autoScrollPxPerSecond(
        linesPerMinute: 10,
        tokenLines: 1,
        physicalLines: 2,
        lineHeight: 13.5,
      ),
      closeTo(4.5, 0.0001),
    );
  });

  test('нулевые входы — 0', () {
    expect(
      autoScrollPxPerSecond(
        linesPerMinute: 15,
        tokenLines: 0,
        physicalLines: 10,
        lineHeight: 13.5,
      ),
      0,
    );
    expect(
      autoScrollPxPerSecond(
        linesPerMinute: 15,
        tokenLines: 10,
        physicalLines: 0,
        lineHeight: 13.5,
      ),
      0,
    );
  });
}
