// Открывает чат DeepSeek в новой вкладке браузера.
//
// Реализация подменяется условным импортом:
// - веб → [browser_launcher_web.dart] (`package:web`);
// - натив → [browser_launcher_io.dart] (заглушка; вызывается только на вебе).
export 'browser_launcher_io.dart'
    if (dart.library.html) 'browser_launcher_web.dart';
