abstract interface class SongListenSession {
  Future<bool> start();

  Future<void> stop();

  void note(String tag);
}
