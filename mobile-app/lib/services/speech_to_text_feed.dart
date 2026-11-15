import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'heard_feed.dart';

final class SpeechToTextFeed implements HeardFeed {
  SpeechToTextFeed({this.onDevice = false, this.pauseFor});

  final bool onDevice;
  final Duration? pauseFor;

  final SpeechToText _speech = SpeechToText();
  final _events = StreamController<HeardEvent>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _levels = StreamController<double>.broadcast();
  bool _ready = false;

  @override
  Stream<HeardEvent> get events => _events.stream;

  @override
  Stream<String> get statuses => _statuses.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onStatus: _statuses.add,
        onError: (e) => _errors.add(e.errorMsg),
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> start(String? localeId) async {
    await _speech.listen(
      onResult: (r) => _events.add(HeardEvent(
        sessionText: r.recognizedWords.trim(),
        confidence: r.confidence,
        isFinal: r.finalResult,
        altCount: r.alternates.length,
      )),
      onSoundLevelChange: _levels.add,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
        pauseFor: pauseFor,
        onDevice: onDevice,
      ),
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
    await _events.close();
    await _statuses.close();
    await _errors.close();
    await _levels.close();
  }
}
