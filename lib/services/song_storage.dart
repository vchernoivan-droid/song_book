import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/song.dart';
import 'file_song_store.dart';
import 'prefs_song_store.dart';

/// Точка доступа к хранилищу песен.
///
/// Реализация выбирается автоматически:
/// - веб → [PrefsSongStorage] (через `shared_preferences`),
/// - мобайл/десктоп → [FileSongStorage] (реальные `.txt`-файлы).
abstract class SongStorage {
  factory SongStorage() {
    if (kIsWeb) return PrefsSongStorage();
    return FileSongStorage();
  }

  Future<List<Song>> listSongs();

  /// Создаёт или перезаписывает песню. [oldFileName] передаём при
  /// редактировании существующей. Возвращает итоговое имя.
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  });

  Future<void> deleteSong(String fileName);

  /// Один раз при первом запуске добавляет пример.
  Future<void> seedIfFirstRun();
}
