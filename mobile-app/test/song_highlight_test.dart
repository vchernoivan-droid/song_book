import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/song_highlight.dart';

const _header = Color(0xFF2E7D32);
const _chord = Color(0xFF1565C0);

List<(String, Color?)> flat(String text) => [
      for (final s in songHighlightSpans(text,
          headerColor: _header, chordColor: _chord))
        if (s is TextSpan) (s.text!, s.style?.color),
    ];

void main() {
  test('спаны покрывают текст без потерь и дублей', () {
    const text = '[Куплет 1]\nAm      Dm\nтекст\n\n[Припев]\n';
    expect(flat(text).map((t) => t.$1).join(), text);
  });

  test('заголовок секции зелёный, аккорды синие, текст без цвета', () {
    const text = '[Припев]\nF       C\nХорошо поём';
    expect(flat(text), [
      ('[Припев]', _header),
      ('\n', null),
      ('F', _chord),
      ('       ', null),
      ('C', _chord),
      ('\n', null),
      ('Хорошо поём', null),
    ]);
  });

  test('заголовок не в начале блока не подсвечивается', () {
    const text = 'Am      Dm\nтекст\n[Припев]\nF  C';
    expect(flat(text), [
      ('Am', _chord),
      ('      ', null),
      ('Dm', _chord),
      ('\n', null),
      ('текст', null),
      ('\n', null),
      ('[Припев]', null),
      ('\n', null),
      ('F', _chord),
      ('  ', null),
      ('C', _chord),
    ]);
  });

  test('слова-ловушки в текстовой строке не подсвечиваются', () {
    const text = 'Am I wrong';
    expect(flat(text), [('Am I wrong', null)]);
  });

  test('пометки аккордной строки не подсвечиваются', () {
    const text = 'Am  2x';
    expect(flat(text), [
      ('Am', _chord),
      ('  2x', null),
    ]);
  });

  test('пустой текст — пустые спаны', () {
    expect(songHighlightSpans('', headerColor: _header, chordColor: _chord),
        isEmpty);
  });
}
