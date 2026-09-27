import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

/// Превращает HTML-страницу в читаемый текст, по возможности сохраняя
/// блоки аккордов и табулатур (обычно они лежат в <pre> / <code>).
String extractReadableText(String htmlSource) {
  final doc = parse(htmlSource);

  final wikiTab = _wikiTabFromStore(doc);
  if (wikiTab != null) return _normalize(wikiTab);

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

String? _wikiTabFromStore(dom.Document doc) {
  for (final el in doc.querySelectorAll('[data-content]')) {
    final raw = el.attributes['data-content'];
    if (raw == null || raw.trim().isEmpty) continue;
    final Object? data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    final content = _wikiTabContent(data);
    if (content == null || content.trim().isEmpty) continue;
    return content
        .replaceAll('[ch]', '')
        .replaceAll('[/ch]', '')
        .replaceAll('[tab]', '')
        .replaceAll('[/tab]', '')
        .replaceAll('\r\n', '\n');
  }
  return null;
}

String? _wikiTabContent(Object? data) {
  if (data is! Map) return null;
  final tabView = data['tab_view'];
  if (tabView is! Map) return null;
  final wikiTab = tabView['wiki_tab'];
  if (wikiTab is! Map) return null;
  final content = wikiTab['content'];
  return content is String ? content : null;
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
