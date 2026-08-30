import 'dart:convert';

import 'package:http/http.dart' as http;

import 'web_search.dart' show WebSource;

class DeepSeekException implements Exception {
  final String message;
  const DeepSeekException(this.message);

  @override
  String toString() => message;
}

/// Обёртка над DeepSeek (OpenAI-совместимый API). Здесь модель НЕ сочиняет
/// песню по памяти, а переформатирует уже загруженный текст со страниц.
class DeepSeekSongService {
  DeepSeekSongService(this.apiKey);

  final String apiKey;

  static const _endpoint = 'https://api.deepseek.com/chat/completions';
  static const _model = 'deepseek-chat';
  static const _temperature = 0.3;

  List<Map<String, String>> _messagesFor(String query, List<WebSource> sources) {
    final sourcesBlock = sources.asMap().entries.map((e) {
      final s = e.value;
      final text = s.text.length > 3000
          ? '${s.text.substring(0, 3000)}…'
          : s.text;
      return '=== ${s.host} ===\n$text';
    }).join('\n\n');

    return [
      const {
        'role': 'system',
        'content': 'Ты — помощник гитариста. Тебе дают сырой текст, '
            'собранный со страниц интернета о песне. Сделай из него аккуратный '
            'разбор для гитары: сначала коротко — тональность и бой/перебор '
            '(если они есть в тексте), затем сама песня по секциям — '
            '[Вступление], [Куплет], [Припев] и т.д., причём гитарные аккорды '
            'стоят отдельной строкой над каждой строкой текста. Убери рекламу, '
            'меню, комментарии и прочий мусор. В ответе — только разбор, без '
            'приветствий, пояснений и markdown-разметки.',
      },
      {
        'role': 'user',
        'content': 'Песня «$query». Вот сырой текст со страниц:\n\n'
            '$sourcesBlock\n\n'
            'Сделай из этого аккуратный разбор для гитары с аккордами над '
            'словами. Если в тексте вообще нет аккордов — напиши коротко, '
            'что аккордов не найдено.',
      },
    ];
  }

  /// Отладочный вид запроса (без дублирования всего текста источников).
  String describeRequest(String query, List<WebSource> sources) {
    final preview = apiKey.length > 4 ? apiKey.substring(0, 4) : apiKey;
    final maskedKey = apiKey.isEmpty ? '(пусто)' : '$preview…(скрыт)';
    final buf = StringBuffer()
      ..writeln('POST $_endpoint')
      ..writeln('Authorization: Bearer $maskedKey')
      ..writeln('model: $_model  | temperature: $_temperature')
      ..writeln('источников: ${sources.length} '
          '(${sources.map((s) => s.host).join(', ')})')
      ..writeln();
    for (final m in _messagesFor(query, sources)) {
      final content = m['content']!;
      final shown =
          content.length > 500 ? '${content.substring(0, 500)}…' : content;
      buf
        ..writeln('[${m['role']}]')
        ..writeln(shown)
        ..writeln();
    }
    return buf.toString().trimRight();
  }

  /// Форматирует загруженные [sources] в разбор песни. Бросает
  /// [DeepSeekException] при ошибках сети/API.
  Future<String> format({
    required String query,
    required List<WebSource> sources,
  }) async {
    if (apiKey.isEmpty) {
      throw const DeepSeekException('Не задан API-ключ DeepSeek.');
    }

    final res = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': _model,
            'stream': false,
            'temperature': _temperature,
            'messages': _messagesFor(query, sources),
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw DeepSeekException('DeepSeek вернул статус ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      throw const DeepSeekException('Некорректный ответ DeepSeek');
    }

    final error = data['error'];
    if (error is Map<String, dynamic>) {
      throw DeepSeekException(
        (error['message'] as String?) ?? 'Ошибка DeepSeek',
      );
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const DeepSeekException('Пустой ответ DeepSeek');
    }

    final message = (choices[0] as Map<String, dynamic>)['message'];
    final content = (message as Map<String, dynamic>)['content'];
    return (content as String? ?? '').trim();
  }
}
