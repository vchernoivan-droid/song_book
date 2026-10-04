/// Заглушка для нативных платформ. На нативе генерация идёт внутри приложения,
/// поэтому эта функция никогда не должна вызываться.
void openDeepSeekInTab(String query) {
  throw UnsupportedError('openDeepSeekInTab доступен только в вебе');
}
