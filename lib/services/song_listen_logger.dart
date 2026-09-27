import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef SongListenLoggerFactory = SongListenLogger Function({
  required String title,
  required int scrollSpeed,
  required int fontSize,
  required double Function() position,
});

class SongListenLogger {
  SongListenLogger({
    required this.title,
    required this.scrollSpeed,
    required this.fontSize,
    required this.position,
  });

  final String title;
  final int scrollSpeed;
  final int fontSize;
  final double Function() position;

  final _speech = SpeechToText();
  IOSink? _sink;
  File? _file;
  Future<void> _flushChain = Future.value();
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stopping = false;

  Future<bool> start() async {
    final base = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(base.path, 'logs'));
    logsDir.createSync(recursive: true);
    final name = '${_sanitize(title)}.${_stamp(DateTime.now())}.log';
    _file = File(p.join(logsDir.path, name));
    _sink = _file!.openWrite();
    _write('# song: $title');
    _write('# scrollSpeed: $scrollSpeed  fontSize: $fontSize');
    _write('# file: ${_file!.path}');

    final ok = await _speech.initialize(onStatus: _onStatus, onError: _onError);
    if (!ok || _stopping) {
      await _close(deleteFile: true);
      return false;
    }
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _write('error: listen: $e');
      await _close(deleteFile: true);
      return false;
    }
    if (_stopping) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
    return true;
  }

  Future<void> stop() async {
    _stopping = true;
    try {
      await _speech.stop();
    } catch (_) {}
    _write('stop');
    await _close();
  }

  void note(String tag) => _write('note: $tag');

  void _onStatus(String status) => _write('status: $status');

  void _onError(SpeechRecognitionError error) =>
      _write('error: ${error.errorMsg}');

  void _onSoundLevel(double level) {
    final now = DateTime.now();
    if (now.difference(_lastLevelAt).inMilliseconds < 500) return;
    _lastLevelAt = now;
    _write('level: ${level.toStringAsFixed(1)} dB');
  }

  void _onResult(SpeechRecognitionResult result) {
    _write(
      '${result.finalResult ? 'final' : 'partial'} '
      'conf=${result.confidence.toStringAsFixed(2)} '
      'alt=${result.alternates.length} '
      'pos=${position().toStringAsFixed(2)}: ${result.recognizedWords}',
    );
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
