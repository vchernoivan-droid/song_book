import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class TagStore {
  static const _dataKey = 'tags_data';

  static int _byTagLower(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    return la == lb ? a.compareTo(b) : la.compareTo(lb);
  }

  @visibleForTesting
  static Future<TagStore> seeded(Map<String, List<String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey, jsonEncode(data));
    return TagStore();
  }

  Future<Map<String, List<String>>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return {
        for (final e in decoded.entries)
          e.key.toString(): [for (final v in e.value as List) v.toString()]
      };
    }
    return {};
  }

  Future<List<String>> allTags() async {
    final data = await all();
    return data.values.expand((tags) => tags).toSet().toList()..sort(_byTagLower);
  }

  Future<List<String>> tagsOf(String fileName) async {
    final data = await all();
    return [...?data[fileName]];
  }

  Future<void> renameTag(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await all();
    for (final e in data.entries) {
      data[e.key] = _normalize([
        for (final t in e.value)
          if (t == oldName) newName else t,
      ]);
    }
    await prefs.setString(_dataKey, jsonEncode(data));
  }

  Future<void> deleteTag(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await all();
    data.forEach((file, tags) {
      data[file] = _normalize(tags.where((t) => t != name).toList());
    });
    data.removeWhere((_, tags) => tags.isEmpty);
    await prefs.setString(_dataKey, jsonEncode(data));
  }

  Future<void> deleteSong(String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await all();
    data.remove(fileName);
    await prefs.setString(_dataKey, jsonEncode(data));
  }

  Future<void> setTags(String fileName, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await all();
    final normalized = _normalize(tags);
    if (normalized.isEmpty) {
      data.remove(fileName);
    } else {
      data[fileName] = normalized;
    }
    await prefs.setString(_dataKey, jsonEncode(data));
  }

  List<String> _normalize(List<String> tags) {
    final result = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    result.sort(_byTagLower);
    return result;
  }
}
