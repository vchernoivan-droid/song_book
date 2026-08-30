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

  /// Сохранённый размер шрифта просмотра (10…28).
  final int fontSize;

  /// Сохранённая скорость автоскролла в строках в минуту (1…60).
  final int scrollSpeed;

  const Song({
    required this.fileName,
    required this.title,
    required this.content,
    this.transpose = 0,
    this.fontSize = 15,
    this.scrollSpeed = 15,
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
    int? fontSize,
    int? scrollSpeed,
  }) {
    return Song(
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      content: content ?? this.content,
      transpose: transpose ?? this.transpose,
      fontSize: fontSize ?? this.fontSize,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
    );
  }

  static final RegExp _transposeHeader = RegExp(
    r'^#\s*transpose\s*:\s*([+-]?\d+)\s*$',
    caseSensitive: false,
  );
  static final RegExp _fontHeader = RegExp(
    r'^#\s*font\s*:\s*(\d+)\s*$',
    caseSensitive: false,
  );
  static final RegExp _scrollHeader = RegExp(
    r'^#\s*scroll\s*:\s*(\d+)\s*$',
    caseSensitive: false,
  );

  /// Разбирает сырой файл: в начале может идти блок шапок
  /// «# transpose: +4» и «# font: 15».
  factory Song.fromRaw({
    required String fileName,
    required String title,
    required String rawContent,
  }) {
    var transpose = 0;
    var fontSize = 15;
    var scrollSpeed = 15;
    final lines = rawContent.split('\n');
    var i = 0;
    while (i < lines.length) {
      final t = _transposeHeader.firstMatch(lines[i]);
      if (t != null) {
        var v = int.tryParse(t.group(1)!) ?? 0;
        if (v > 11) v = 11;
        if (v < -11) v = -11;
        transpose = v;
        i++;
        continue;
      }
      final f = _fontHeader.firstMatch(lines[i]);
      if (f != null) {
        var v = int.tryParse(f.group(1)!) ?? 15;
        if (v > 28) v = 28;
        if (v < 10) v = 10;
        fontSize = v;
        i++;
        continue;
      }
      final s = _scrollHeader.firstMatch(lines[i]);
      if (s != null) {
        var v = int.tryParse(s.group(1)!) ?? 15;
        if (v > 60) v = 60;
        if (v < 1) v = 1;
        scrollSpeed = v;
        i++;
        continue;
      }
      break;
    }
    return Song(
      fileName: fileName,
      title: title,
      content: lines.skip(i).join('\n'),
      transpose: transpose,
      fontSize: fontSize,
      scrollSpeed: scrollSpeed,
    );
  }

  /// Сырой текст для записи в хранилище — с шапками настроек.
  String get rawContent => withHeaders(
        transpose: transpose,
        fontSize: fontSize,
        scrollSpeed: scrollSpeed,
        body: content,
      );

  /// Склейка шапок «# transpose: …», «# font: …» и «# scroll: …» с телом.
  static String withHeaders({
    required int transpose,
    required int fontSize,
    required int scrollSpeed,
    required String body,
  }) {
    final header = <String>[];
    if (transpose != 0) {
      final sign = transpose > 0 ? '+' : '';
      header.add('# transpose: $sign$transpose');
    }
    if (fontSize != 15) {
      header.add('# font: $fontSize');
    }
    if (scrollSpeed != 15) {
      header.add('# scroll: $scrollSpeed');
    }
    if (header.isEmpty) return body;
    return '${header.join('\n')}\n$body';
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
