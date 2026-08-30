import 'deepseek_song_service.dart';
import 'web_fetch.dart';
import 'web_search.dart';

/// Итог конвейера: отформатированный разбор + источники + отладка запроса.
class FoundSong {
  final String title;
  final String content;
  final List<String> sourceHosts;
  final String requestDebug;

  const FoundSong({
    required this.title,
    required this.content,
    required this.sourceHosts,
    required this.requestDebug,
  });
}

/// Конвейер подбора песни: DuckDuckGo-поиск → загрузка top-3 страниц →
/// DeepSeek форматирует сырой текст в аккуратный разбор с аккордами.
class SongFinder {
  SongFinder(this.apiKey);

  final String apiKey;

  Future<FoundSong> find(String query) async {
    final results = await webSearch(query);

    // Грузим top-3 параллельно; неподдающиеся страницы пропускаем.
    final top = results.take(3).toList();
    final fetched = await Future.wait(top.map((r) async {
      try {
        final text = await fetchReadableText(r.url);
        if (text.trim().isNotEmpty) return WebSource(r.title, r.url, text);
      } catch (_) {}
      return null;
    }));
    final sources = fetched.whereType<WebSource>().toList();

    if (sources.isEmpty) {
      throw const WebSearchException(
        'Не удалось найти и загрузить страницы с песней. '
        'Попробуйте уточнить название.',
      );
    }

    final service = DeepSeekSongService(apiKey);
    final content = await service.format(query: query, sources: sources);

    return FoundSong(
      title: query,
      content: content,
      sourceHosts: sources.map((s) => s.host).toList(),
      requestDebug: service.describeRequest(query, sources),
    );
  }
}
