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
  static const int _phraseTailChars = 500;

  String _phraseView() {
    if (_lastPhrase.length <= _phraseTailChars) {
      return _lastPhrase.isEmpty ? '…' : _lastPhrase;
    }
    var tail = _lastPhrase.substring(_lastPhrase.length - _phraseTailChars);
    final wordStart = tail.indexOf(RegExp(r'\s'));
    if (wordStart >= 0) tail = tail.substring(wordStart + 1);
    return '… $tail';
  }

  _Phase _phase = _Phase.idle;
  String _status = '';
  String _sttStatus = '';
  String _lastPhrase = '';
  final _manualCtrl = TextEditingController();

  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _listeningWanted = false;
  String? _activeLocaleId;
  Timer? _restartTimer;
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _closed = false;
  String? _serverUrl;

  static const int _logLimit = 500;
  final List<String> _logLines = [];

  void _log(String line) {
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    String p3(int v) => v.toString().padLeft(3, '0');
    final ts =
        '${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}.${p3(now.millisecond)}';
    _logLines.add('$ts $line');
    if (_logLines.length > _logLimit) {
      _logLines.removeRange(0, _logLines.length - _logLimit);
    }
    debugPrint('RMIC $ts $line');
  }

  @override
  void dispose() {
    _closed = true;
    _listeningWanted = false;
    _restartTimer?.cancel();
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
    _log('connect: пробуем ${urls.length} адрес(ов)');
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
      _log('connect ok: $url');
    } catch (e) {
      _log('connect fail: $url ($e)');
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
        if (decoded['v'] == _protocolVersion) {
          _log('hello v${decoded['v']}');
          return ws;
        }
        _log('hello версия не подходит: v${decoded['v']}');
        if (mounted) {
          setState(() => _status = 'Версия не подходит — обновите приложение');
        }
      }
    } catch (_) {}
    await _dropSocket();
    return null;
  }

  Future<void> _afterHello(WebSocket ws, String url) async {
    _serverUrl = url;
    final speechOk = await _initSpeech();
    _log('speech init: $speechOk');
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
    _log('ready отправлен');
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
        _log('listen от сервера: locale=${decoded['localeId']}');
        unawaited(_startListening(decoded['localeId'] as String?));
      case 'stop':
        _log('stop от сервера');
        unawaited(_stopListening());
    }
  }

  Future<void> _startListening(String? localeId) async {
    _activeLocaleId = localeId;
    _listeningWanted = true;
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          localeId: localeId,
          pauseFor: const Duration(seconds: 10),
          onDevice: true,
        ),
      );
      _log('listen запущен: locale=$localeId');
      if (mounted) setState(() => _phase = _Phase.listening);
    } catch (e) {
      _log('listen упал: $e');
      _send({'type': 'error', 'message': 'Не удалось начать прослушивание'});
      if (mounted) setState(() => _sttStatus = 'не запустилось: $e');
    }
  }

  Future<void> _stopListening() async {
    _listeningWanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
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
    const tailWords = 32;
    if (words.length > tailWords) {
      words.removeRange(0, words.length - tailWords);
    }
    if (mounted) setState(() => _lastPhrase = result.recognizedWords);
    _log(
      '${result.finalResult ? 'final' : 'partial'} '
      'conf=${result.confidence.toStringAsFixed(2)} '
      'words=${words.length}: ${result.recognizedWords.length > 60 ? result.recognizedWords.substring(result.recognizedWords.length - 60) : result.recognizedWords}',
    );
    if (words.isNotEmpty) {
      _send({'type': 'words', 'text': words.join(' ')});
    }
    if (result.finalResult) _scheduleRestart('finalResult');
  }

  void _scheduleRestart(String reason) {
    if (!_listeningWanted || _ws == null || _closed) return;
    _log('рестарт прослушивания: $reason');
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_listeningWanted || _ws == null || _closed) return;
      unawaited(_restartListening());
    });
  }

  Future<void> _restartListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (!_listeningWanted || _ws == null || _closed) return;
    await _startListening(_activeLocaleId);
  }

  void _onSpeechStatus(String status) {
    _log('status: $status');
    if (mounted) setState(() => _sttStatus = status);
    if (status == 'notListening' || status == SpeechToText.doneStatus) {
      _scheduleRestart('status: $status');
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    _log('stt error: ${error.errorMsg}');
    if (mounted) setState(() => _sttStatus = error.errorMsg);
    _send({'type': 'error', 'message': error.errorMsg});
  }

  void _onServerClosed() {
    if (_closed) return;
    _log('сервер закрыл соединение');
    _listeningWanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
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
    _log('disconnect');
    _listeningWanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    await _speech.stop();
    await _dropSocket();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = '';
      _sttStatus = '';
      _lastPhrase = '';
    });
  }

  Future<void> _sendLog() async {
    final serverUrl = _serverUrl;
    if (serverUrl == null || _logLines.isEmpty) return;
    final logUrl = '${serverUrl.replaceFirst('ws://', 'http://')}/log';
    _log('отправка лога: $logUrl');
    if (mounted) setState(() => _status = 'Отправляем лог…');
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(logUrl));
      request.headers.contentType = ContentType.text;
      request.add(utf8.encode(_logLines.join('\n')));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      if (!mounted) return;
      setState(() {
        _status = response.statusCode == 200
            ? 'Лог отправлен'
            : 'Лог не принят: ${response.statusCode}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Лог не ушёл: $e');
    }
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
                    if (_logLines.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => unawaited(_sendLog()),
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Отправить лог'),
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
              if (_sttStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _sttStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        _phraseView(),
                        style: const TextStyle(
                          fontFamily: 'Roboto Mono',
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: () => unawaited(_disconnect()),
                      icon: const Icon(Icons.mic_off),
                      label: const Text('Отключиться'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_sendLog()),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Отправить лог'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}
