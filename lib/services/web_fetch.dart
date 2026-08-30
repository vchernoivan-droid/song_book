import 'package:http/http.dart' as http;

import 'html_text_extractor.dart';

/// User-Agent десктопного браузера: имитируем его, чтобы сайты не банили
/// запросы и не отдавали урезанную мобильную версию.
const kDesktopUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Скачивает страницу по [url] и достаёт из неё читаемый текст.
Future<String> fetchReadableText(String url) async {
  final client = http.Client();
  try {
    final res = await client.get(Uri.parse(url), headers: {
      'User-Agent': kDesktopUserAgent,
      'Accept-Language': 'ru,en;q=0.8',
    }).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('Не удалось загрузить страницу (${res.statusCode})');
    }
    return extractReadableText(res.body);
  } finally {
    client.close();
  }
}
