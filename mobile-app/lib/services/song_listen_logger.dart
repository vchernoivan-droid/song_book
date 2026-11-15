import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:song_book/services/heard_feed.dart';
import 'package:song_book/services/speech_to_text_feed.dart';

import 'song_listen_session.dart';

typedef SongListenLoggerFactory = SongListenLogger Function({
  required String title,
  required int fontSize,
  required String? localeId,
  required double Function() position,
  void Function(String recognizedWords)? onResult,
});

class SongListenLogger implements SongListenSession {
  SongListenLogger({
    required this.title,
    required this.fontSize,
    required this.localeId,
    required this.position,
    this.onResult,
    this.feed,
  });

  final String title;
  final int fontSize;
  final String? localeId;
  final void Function(String recognizedWords)? onResult;
  final double Function() position;
  final HeardFeed? feed;

  late final HeardFeed _feed = feed ?? SpeechToTextFeed();
  final List<StreamSubscription<Object?>> _subs = [];
  IOSink? _sink;
  File? _file;
  Future<void> _flushChain = Future.value();
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stopping = false;

  @override
  Future<bool> start() async {
    final base = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(base.path, 'logs'));
    logsDir.createSync(recursive: true);
    final name = '${_sanitize(title)}.${_stamp(DateTime.now())}.log';
    _file = File(p.join(logsDir.path, name));
    _sink = _file!.openWrite();
    _write('# song: $title');
    _write('# fontSize: $fontSize');
    _write('# file: ${_file!.path}');

    _subs
      ..add(_feed.events.listen(_onResult))
      ..add(_feed.statuses.listen(_onStatus))
      ..add(_feed.errors.listen(_onError))
      ..add(_feed.levels.listen(_onSoundLevel));
    final ok = await _feed.initialize();
    if (!ok || _stopping) {
      await _close(deleteFile: true);
      return false;
    }
    try {
      await _feed.start(localeId);
    } catch (e) {
      _write('error: listen: $e');
      await _close(deleteFile: true);
      return false;
    }
    if (_stopping) {
      await _feed.cancel();
    }
    return true;
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    await _feed.stop();
    _write('stop');
    await _close();
  }

  @override
  void note(String tag) => _write('note: $tag');

  void _onStatus(String status) => _write('status: $status');

  void _onError(String message) => _write('error: $message');

  void _onSoundLevel(double level) {
    final now = DateTime.now();
    if (now.difference(_lastLevelAt).inMilliseconds < 500) return;
    _lastLevelAt = now;
    _write('level: ${level.toStringAsFixed(1)} dB');
  }

  void _onResult(HeardEvent event) {
    _write(
      '${event.isFinal ? 'final' : 'partial'} '
      'conf=${event.confidence.toStringAsFixed(2)} '
      'alt=${event.altCount} '
      'pos=${position().toStringAsFixed(2)}: ${event.sessionText}',
    );
    onResult?.call(event.sessionText);
  }

  void _write(String line) {
    final withTs = '${_ts()} $line';
    debugPrint('STT $withTs');
    final sink = _sink;
    if (sink != null) {
      sink.writeln(withTs);
      // IOSink не терпит параллельных операций — flush строго по цепочке.
      _flushChain = _flushChain
          .then((_) => sink.flush())
          .catchError((_) {});
    }
  }

  Future<void> _close({bool deleteFile = false}) async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await _flushChain;
      await sink.close();
    }
    final file = _file;
    _file = null;
    if (deleteFile && file != null && file.existsSync()) {
      file.deleteSync();
    }
  }

  static String? localeIdFor(String content) {
    final cyrillic =
        RegExp(r'\p{Script=Cyrillic}', unicode: true).allMatches(content).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(content).length;
    if (cyrillic == 0 && latin == 0) return null;
    return cyrillic >= latin ? 'ru-RU' : 'en-US';
  }

  String _ts() {
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    String p3(int v) => v.toString().padLeft(3, '0');
    return '${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}.${p3(now.millisecond)}';
  }

  String _stamp(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(t.year % 100)}-${p2(t.month)}-${p2(t.day)}-'
        '${p2(t.hour)}-${p2(t.minute)}';
  }

  String _sanitize(String name) {
    var s = name.trim().replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    return s.isEmpty ? 'Без названия' : s;
  }
}
