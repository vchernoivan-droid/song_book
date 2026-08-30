import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'example_song.dart';
import 'song_storage.dart';

/// Веб-хранилище: песни лежат одной JSON-картой в `shared_preferences`
/// (в браузере нет файловой системы). Ключ — имя «файла», значение — текст.
class PrefsSongStorage implements SongStorage {
  static const _dataKey = 'songs_data';
  static const _seededKey = 'songs_seeded';
  static const _ext = '.txt';

  Future<Map<String, String>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return {
        for (final e in decoded.entries) e.key.toString(): e.value.toString()
      };
    }
    return {};
  }

  Future<void> _writeAll(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey, jsonEncode(data));
  }

  String _titleFromName(String fileName) => fileName.endsWith(_ext)
      ? fileName.substring(0, fileName.length - _ext.length)
      : fileName;

  String _sanitize(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    if (s.isEmpty) s = 'Без названия';
    return s;
  }

  String _uniqueName(
      Map<String, String> data, String baseName, String? exclude) {
    var name = '$baseName$_ext';
    var i = 2;
    while (name != exclude && data.containsKey(name)) {
      name = '$baseName ($i)$_ext';
      i++;
    }
    return name;
  }

  @override
  Future<List<Song>> listSongs() async {
    final data = await _readAll();
    final names = data.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names
        .map((n) => Song.fromRaw(
              fileName: n,
              title: _titleFromName(n),
              rawContent: data[n]!,
            ))
        .toList();
  }

  @override
  Future<String> writeSong({
    required String desiredTitle,
    required String content,
    String? oldFileName,
  }) async {
    final data = await _readAll();
    final base = _sanitize(desiredTitle);
    final name = _uniqueName(data, base, oldFileName);

    data[name] = content;
    if (oldFileName != null && oldFileName != name) {
      data.remove(oldFileName);
    }
    await _writeAll(data);
    return name;
  }

  @override
  Future<void> deleteSong(String fileName) async {
    final data = await _readAll();
    data.remove(fileName);
    await _writeAll(data);
  }

  @override
  Future<void> seedIfFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) == true) return;

    final data = await _readAll();
    if (data.isEmpty) {
      data['$kExampleSongTitle$_ext'] = kExampleSongContent;
      await _writeAll(data);
    }
    await prefs.setBool(_seededKey, true);
  }
}
