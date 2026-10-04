import 'package:web/web.dart' as web;

/// Открывает чат DeepSeek с запросом [query] в новой вкладке браузера.
///
/// Вызывается из обработчика кнопки, т.е. в контексте пользовательского жеста,
/// поэтому блокировщики всплывающих окон этому окну не мешают.
void openDeepSeekInTab(String query) {
  final url = 'https://chat.deepseek.com/?q=${Uri.encodeQueryComponent(query)}';
  web.window.open(url, '_blank');
}
