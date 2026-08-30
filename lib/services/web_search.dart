import 'package:html/parser.dart';
import 'package:http/http.dart' as http;

import 'web_fetch.dart' show kDesktopUserAgent;

/// Найденная поисковиком страница.
class SearchResult {
  final String title;
  final String url;

  const SearchResult(this.title, this.url);

  String get host {
    final uri = Uri.tryParse(url);
    return (uri != null && uri.host.isNotEmpty) ? uri.host : url;
  }
}

/// Загруженная страница: заголовок + url + извлечённый текст.
class WebSource {
  final String title;
  final String url;
  final String text;

  const WebSource(this.title, this.url, this.text);

  String get host {
    final uri = Uri.tryParse(url);
    return (uri != null && uri.host.isNotEmpty) ? uri.host : url;
  }
}

class WebSearchException implements Exception {
  final String message;
  const WebSearchException(this.message);

  @override
  String toString() => message;
}

/// Поиск через html-версию DuckDuckGo (без API-ключа). К запросу дописываем
/// «аккорды», чтобы результаты вели на сайты с аккордами/табами.
Future<List<SearchResult>> webSearch(String query) async {
  final effective = '$query аккорды';
  final uri = Uri.parse(
      'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(effective)}');
  final client = http.Client();
  try {
    final res = await client.get(uri, headers: {
      'User-Agent': kDesktopUserAgent,
      'Accept-Language': 'ru,en;q=0.8',
    }).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw WebSearchException('Поисковик вернул статус ${res.statusCode}');
    }
    return _parseResults(res.body);
  } finally {
    client.close();
  }
}

List<SearchResult> _parseResults(String htmlSource) {
  final doc = parse(htmlSource);
  final anchors = doc.querySelectorAll('a.result__a, a.result-link');

  final out = <SearchResult>[];
  final seen = <String>{};
  for (final a in anchors) {
    final href = a.attributes['href'] ?? '';
    final url = _resolveUrl(href);
    if (url == null) continue;
    final title = a.text.trim();
    if (title.isEmpty || !seen.add(url)) continue;
    out.add(SearchResult(title, url));
    if (out.length >= 8) break;
  }
  return out;
}

/// DuckDuckGo заворачивает реальные ссылки в редирект `...?uddg=<encoded>`.
String? _resolveUrl(String href) {
  final match = RegExp(r'uddg=([^&]+)').firstMatch(href);
  final raw = match != null ? Uri.decodeComponent(match.group(1)!) : href;
  if (raw.isEmpty) return null;
  var url = raw;
  if (url.startsWith('//')) url = 'https:$url';
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return url;
}
