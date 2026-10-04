import 'package:shared_preferences/shared_preferences.dart';

/// Хранение API-ключа DeepSeek в `shared_preferences` (только на устройстве).
class DeepSeekCredentials {
  static const _kApiKey = 'deepseek_api_key';

  const DeepSeekCredentials._();

  static Future<String> readApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? '';
  }

  static Future<void> save(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, apiKey.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKey);
  }

  static Future<bool> isConfigured() async =>
      (await readApiKey()).isNotEmpty;
}
