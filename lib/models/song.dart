/// Одна песня = один файл в постоянном каталоге приложения.
class Song {
  /// Имя файла, например "Hotel_California.txt".
  final String fileName;

  /// Отображаемое название (имя файла без расширения).
  final String title;

  /// Текст песни (аккорды / табы / текст) без служебной шапки.
  final String content;

  /// Сохранённое транспонирование в полутонах (−11…+11).
  final int transpose;

  const Song({
    required this.fileName,
    required this.title,
    required this.content,
    this.transpose = 0,
  });

  /// Короткий текст-превью для списка — первая непустая строка.
  String get preview {
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return 'Пусто';
  }

  Song copyWith({
    String? fileName,
    String? title,
    String? content,
    int? transpose,
  }) {
    return Song(
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      content: content ?? this.content,
      transpose: transpose ?? this.transpose,
    );
  }

  static final RegExp _transposeHeader = RegExp(
    r'^#\s*transpose\s*:\s*([+-]?\d+)\s*$',
    caseSensitive: false,
  );

  /// Разбирает сырой файл: первая строка может быть «# transpose: +4».
  factory Song.fromRaw({
    required String fileName,
    required String title,
    required String rawContent,
  }) {
    final newline = rawContent.indexOf('\n');
    final firstLine = newline == -1 ? rawContent : rawContent.substring(0, newline);
    final match = _transposeHeader.firstMatch(firstLine);
    if (match == null) {
      return Song(fileName: fileName, title: title, content: rawContent);
    }

    var value = int.tryParse(match.group(1)!) ?? 0;
    if (value > 11) value = 11;
    if (value < -11) value = -11;
    final body = newline == -1 ? '' : rawContent.substring(newline + 1);
    return Song(
      fileName: fileName,
      title: title,
      content: body,
      transpose: value,
    );
  }

  /// Сырой текст для записи в хранилище — с шапкой транспонирования.
  String get rawContent => withTransposeHeader(transpose, content);

  /// Склейка шапки «# transpose: …» с телом песни.
  static String withTransposeHeader(int transpose, String body) {
    if (transpose == 0) return body;
    final sign = transpose > 0 ? '+' : '';
    return '# transpose: $sign$transpose\n$body';
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
