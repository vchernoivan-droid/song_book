import 'dart:async';

abstract interface class HeardFeed {
  Stream<HeardEvent> get events;
  Stream<String> get statuses;
  Stream<String> get errors;
  Stream<double> get levels;
  Future<bool> initialize();
  Future<void> start(String? localeId);
  Future<void> stop();
  Future<void> cancel();
}

final class HeardEvent {
  final String sessionText;
  final double confidence;
  final bool isFinal;
  final int altCount;

  const HeardEvent({
    required this.sessionText,
    required this.confidence,
    required this.isFinal,
    this.altCount = 0,
  });
}

final class ReplayHeardFeed implements HeardFeed {
  final List<HeardEvent> script;
  final Duration delay;
  final _events = StreamController<HeardEvent>.broadcast(sync: true);

  ReplayHeardFeed({required this.script, this.delay = Duration.zero});

  @override
  Stream<HeardEvent> get events => _events.stream;

  @override
  Stream<String> get statuses => const Stream.empty();

  @override
  Stream<String> get errors => const Stream.empty();

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> start(String? localeId) async {
    for (final event in script) {
      _events.add(event);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    await _events.close();
  }
}
