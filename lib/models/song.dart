/// Одна песня = один файл в постоянном каталоге приложения.
class Song {
  /// Имя файла, например "Hotel_California.txt".
  final String fileName;

  /// Отображаемое название (имя файла без расширения).
  final String title;

  /// Полный текст песни (аккорды / табы / текст).
  final String content;

  const Song({
    required this.fileName,
    required this.title,
    required this.content,
  });

  /// Короткий текст-превью для списка — первая непустая строка.
  String get preview {
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return 'Пусто';
  }
}

class SongWithPreview {
  final String? preview;
  final Song song;

  SongWithPreview({
    required this.preview,
    required this.song,
  });
}
