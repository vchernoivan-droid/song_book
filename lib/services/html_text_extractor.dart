import 'package:html/parser.dart';

/// Превращает HTML-страницу в читаемый текст, по возможности сохраняя
/// блоки аккордов и табулатур (обычно они лежат в <pre> / <code>).
String extractReadableText(String htmlSource) {
  final doc = parse(htmlSource);

  for (final selector in [
    'script',
    'style',
    'nav',
    'header',
    'footer',
    'aside',
    'form',
    'noscript',
    'svg',
    'iframe',
  ]) {
    doc.querySelectorAll(selector).forEach((e) => e.remove());
  }

  final pre = doc.querySelectorAll('pre');
  if (pre.isNotEmpty) {
    final text =
        pre.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join('\n\n');
    if (text.trim().isNotEmpty) return _normalize(text);
  }

  final main = doc.querySelector('main, article, [role="main"]');
  final source = main ?? doc.body;
  return _normalize(source?.text ?? '');
}

String _normalize(String input) {
  final lines =
      input.split(RegExp(r'\r\n|\r|\n')).map((l) => l.trimRight()).toList();

  final out = <String>[];
  var blanks = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) {
      if (blanks == 0) out.add('');
      blanks++;
    } else {
      out.add(line);
      blanks = 0;
    }
  }

  var result = out.join('\n').trim();
  if (result.length > 20000) result = '${result.substring(0, 20000)}…';
  return result;
}
