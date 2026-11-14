import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum _Phase { idle, connecting, connected, listening }

class RemoteMicScreen extends StatefulWidget {
  const RemoteMicScreen({super.key});

  @override
  State<RemoteMicScreen> createState() => _RemoteMicScreenState();
}

class _RemoteMicScreenState extends State<RemoteMicScreen> {
  static const int _protocolVersion = 1;
  static const int _tailWords = 32;

  _Phase _phase = _Phase.idle;
  String _status = '';
  String _lastPhrase = '';
  final _manualCtrl = TextEditingController();

  final _speech = SpeechToText();
  bool _speechReady = false;
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.close();
    _speech.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _onQr(String raw) {
    if (_phase != _Phase.idle) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final port = decoded['port'];
    final ips = decoded['ips'];
    if (port is! int || ips is! List) return;
    final urls = [
      for (final ip in ips)
        if (ip is String) 'ws://$ip:$port',
    ];
    if (urls.isEmpty) return;
    unawaited(_connect(urls));
  }

  Future<void> _connectManual() async {
    if (_phase != _Phase.idle) return;
    final raw = _manualCtrl.text.trim();
    if (raw.isEmpty) return;
    final hostPort = raw.startsWith('ws://') ? raw.substring(5) : raw;
    await _connect(['ws://$hostPort']);
  }

  Future<void> _connect(List<String> urls) async {
    setState(() {
      _phase = _Phase.connecting;
      _status = 'Подключаемся…';
    });
    for (final url in urls) {
      final ws = await _tryOne(url);
      if (ws != null) {
        await _afterHello(ws, url);
        return;
      }
      if (_closed || !mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = 'Компьютер не найден';
    });
  }

  Future<WebSocket?> _tryOne(String url) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(url).timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
    final hello = Completer<Object?>();
    _wsSub?.cancel();
    _wsSub = ws.listen(
      (dynamic data) {
        if (!hello.isCompleted) {
          hello.complete(data);
          return;
        }
        _onServerMessage(data);
      },
      onDone: () {
        if (!hello.isCompleted) hello.completeError(StateError('closed'));
        _onServerClosed();
      },
      onError: (Object e) {
        if (!hello.isCompleted) hello.completeError(e);
        _onServerClosed();
      },
      cancelOnError: false,
    );
    _ws = ws;
    try {
      final raw = await hello.future.timeout(const Duration(seconds: 2));
      final decoded = jsonDecode(raw as String);
      if (decoded is Map<String, Object?> && decoded['type'] == 'hello') {
        if (decoded['v'] == _protocolVersion) return ws;
        if (mounted) {
          setState(() => _status = 'Версия не подходит — обновите приложение');
        }
      }
    } catch (_) {}
    await _dropSocket();
    return null;
  }

  Future<void> _afterHello(WebSocket ws, String url) async {
    final speechOk = await _initSpeech();
    if (_closed || !mounted) return;
    if (!speechOk) {
      _send({'type': 'error', 'message': 'Микрофон недоступен'});
      await _dropSocket();
      setState(() {
        _phase = _Phase.idle;
        _status = 'Микрофон недоступен';
      });
      return;
    }
    _send({'type': 'ready'});
    setState(() {
      _phase = _Phase.connected;
      _status = 'Подключено: $url';
      _lastPhrase = '';
    });
  }

  Future<bool> _initSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  void _onServerMessage(dynamic data) {
    final Object? decoded;
    try {
      decoded = jsonDecode(data as String);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'listen':
        unawaited(_startListening(decoded['localeId'] as String?));
      case 'stop':
        unawaited(_stopListening());
    }
  }

  Future<void> _startListening(String? localeId) async {
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          localeId: localeId,
        ),
      );
      if (mounted) setState(() => _phase = _Phase.listening);
    } catch (_) {
      _send({'type': 'error', 'message': 'Не удалось начать прослушивание'});
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (mounted && _phase == _Phase.listening) {
      setState(() => _phase = _Phase.connected);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length > _tailWords) {
      words.removeRange(0, words.length - _tailWords);
    }
    if (mounted) setState(() => _lastPhrase = result.recognizedWords);
    if (words.isEmpty) return;
    _send({'type': 'words', 'text': words.join(' ')});
  }

  void _onSpeechStatus(String status) {
    if (status == 'notListening' && mounted && _phase == _Phase.listening) {
      setState(() => _phase = _Phase.connected);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    _send({'type': 'error', 'message': error.errorMsg});
  }

  void _onServerClosed() {
    if (_closed) return;
    _ws = null;
    _speech.stop();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = 'Компьютер отключился';
      _lastPhrase = '';
    });
  }

  void _send(Map<String, Object?> message) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> _dropSocket() async {
    await _wsSub?.cancel();
    _wsSub = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }
  }

  Future<void> _disconnect() async {
    await _speech.stop();
    await _dropSocket();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = '';
      _lastPhrase = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Беспроводной микрофон')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.idle || _Phase.connecting => Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      onDetect: (BarcodeCapture capture) {
                        for (final barcode in capture.barcodes) {
                          final raw = barcode.rawValue;
                          if (raw != null) _onQr(raw);
                        }
                      },
                    ),
                    if (_phase == _Phase.connecting)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Адрес вручную',
                              hintText: '192.168.1.2:54321',
                              isDense: true,
                            ),
                            onSubmitted: (_) => unawaited(_connectManual()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Подключить',
                          onPressed:
                              _phase == _Phase.idle
                                  ? () => unawaited(_connectManual())
                                  : null,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                    if (_status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _Phase.connected || _Phase.listening => Column(
            children: [
              const SizedBox(height: 24),
              Icon(
                _phase == _Phase.listening
                    ? Icons.graphic_eq
                    : Icons.smartphone,
                size: 48,
                color:
                    _phase == _Phase.listening
                        ? Colors.green.shade700
                        : Colors.amber.shade800,
              ),
              const SizedBox(height: 8),
              Text(
                _phase == _Phase.listening
                    ? 'Слушаем и передаём'
                    : 'Подключено, ждём запуск песни',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    _lastPhrase.isEmpty ? '…' : _lastPhrase,
                    style: const TextStyle(fontFamily: 'Roboto Mono'),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => unawaited(_disconnect()),
                  icon: const Icon(Icons.mic_off),
                  label: const Text('Отключиться'),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}
