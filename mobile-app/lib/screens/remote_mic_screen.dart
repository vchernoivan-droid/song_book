import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:song_book/services/heard_feed.dart';
import 'package:song_book/services/heard_stitcher.dart';
import 'package:song_book/services/song_parser.dart';
import 'package:song_book/services/speech_to_text_feed.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum _Phase { idle, connecting, connected, listening }

class RemoteMicScreen extends StatefulWidget {
  const RemoteMicScreen({super.key, this.feed});

  final HeardFeed? feed;

  @override
  State<RemoteMicScreen> createState() => _RemoteMicScreenState();
}

class _RemoteMicScreenState extends State<RemoteMicScreen> {
  static const int _protocolVersion = 3;

  Widget _buildSongTab() {
    final lines = _songLines;
    if (lines == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note,
                size: 40,
                color: Theme.of(context).hintColor,
              ),
              const SizedBox(height: 12),
              const Text('Ждём песню от компьютера',
                  style: TextStyle(fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                'Экран не погаснет, пока подключены: пока не умеем беречь батарею — лучше воткнуть зарядку',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: _buildSongView(),
      ),
    );
  }

  Widget _buildHeardTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              _lastPhrase.isEmpty ? '…' : _lastPhrase,
              style: const TextStyle(
                fontFamily: 'Roboto Mono',
                fontSize: 16,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongView() {
    final lines = _songLines!;
    return SingleChildScrollView(
      controller: _songScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Container(
              key: _songKeys[i],
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: i == _songPos
                  ? BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Text(
                lines[i].isEmpty ? ' ' : lines[i],
                style: TextStyle(
                  fontFamily: 'Roboto Mono',
                  fontSize: 16,
                  height: 1.4,
                  color: i == _songPos ? Colors.white : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _Phase _phase = _Phase.idle;
  String _status = '';
  String _sttStatus = '';
  String _lastPhrase = '';
  List<String>? _songLines;
  int? _songPos;
  final _songKeys = <GlobalKey>[];
  final _songScroll = ScrollController();
  final _manualCtrl = TextEditingController();

  void _setSong(String content, int? transpose) {
    final semis = (((transpose ?? 0) % 12) + 12) % 12;
    final rendered = renderSongLines(parseSong(content).transposed(semis));
    final entries = [
      for (final r in rendered.lines)
        rendered.text.substring(r.start, r.end),
    ];
    _songKeys
      ..clear()
      ..addAll([for (var i = 0; i < entries.length; i++) GlobalKey()]);
    _songLines = entries;
  }

  final HeardStitcher _stitcher = HeardStitcher();
  late final HeardFeed _feed =
      widget.feed ?? SpeechToTextFeed(onDevice: true, pauseFor: const Duration(seconds: 10));
  StreamSubscription<HeardEvent>? _feedSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _levelSub;
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);
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
    if (_ws != null) {
      _send({'type': 'log', 'line': '$ts $line'});
    }
    debugPrint('RMIC $ts $line');
  }

  @override
  void initState() {
    super.initState();
    _feedSub = _feed.events.listen(_onHeardEvent);
    _statusSub = _feed.statuses.listen(_onFeedStatus);
    _errorSub = _feed.errors.listen(_onFeedError);
    _levelSub = _feed.levels.listen(_onFeedLevel);
  }

  @override
  void dispose() {
    _closed = true;
    _listeningWanted = false;
    _restartTimer?.cancel();
    WakelockPlus.disable();
    _feedSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _levelSub?.cancel();
    unawaited(_feed.cancel());
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.close();
    _manualCtrl.dispose();
    _songScroll.dispose();
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
    final speechOk = await _feed.initialize();
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
    unawaited(WakelockPlus.enable());
    setState(() {
      _phase = _Phase.connected;
      _status = 'Подключено: $url';
      _lastPhrase = '';
    });
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
        _stitcher.clearFinals();
        unawaited(_startListening(decoded['localeId'] as String?));
      case 'stop':
        _log('stop от сервера');
        unawaited(_stopListening());
      case 'song':
        final content = decoded['content'];
        if (content is String && content.isNotEmpty) {
          _setSong(content, decoded['transpose'] is int
              ? decoded['transpose'] as int
              : null);
          final pos = decoded['pos'];
          _log('song от сервера: ${_songLines!.length} строк');
          setState(() => _songPos = pos is int ? pos : null);
          _scrollSongTo(_songPos, jump: true);
        } else {
          _log('song от сервера: закрыт');
          setState(() {
            _songLines = null;
            _songPos = null;
          });
        }
      case 'pos':
        final pos = decoded['pos'];
        setState(() => _songPos = pos is int ? pos : null);
        _scrollSongTo(_songPos);
    }
  }

  void _scrollSongTo(int? pos, {bool jump = false}) {
    if (pos == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = pos < _songKeys.length ? _songKeys[pos].currentContext : null;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: jump ? Duration.zero : const Duration(milliseconds: 250),
      );
    });
  }

  Future<void> _startListening(String? localeId) async {
    _activeLocaleId = localeId;
    _listeningWanted = true;
    try {
      await _feed.start(localeId);
      _log('listen запущен: locale=$localeId');
      _stitcher.reset();
      unawaited(WakelockPlus.enable());
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
    await _feed.stop();
    if (mounted && _phase == _Phase.listening) {
      setState(() => _phase = _Phase.connected);
    }
  }

  void _onHeardEvent(HeardEvent event) {
    final res = _stitcher.onEvent(event);
    for (final line in res.logLines) {
      _log(line);
    }
    if (res.phraseView != null && mounted) {
      setState(() => _lastPhrase = res.phraseView!);
    }
    if (res.sendText != null) {
      _send({'type': 'words', 'text': res.sendText});
    }
    if (event.isFinal) _scheduleRestart('finalResult');
  }

  void _onFeedStatus(String status) {
    _log('status: $status');
    if (mounted) setState(() => _sttStatus = status);
    if (status == 'notListening' || status == 'done') {
      _scheduleRestart('status: $status');
    }
  }

  void _onFeedError(String message) {
    _log('stt error: $message');
    if (mounted) setState(() => _sttStatus = message);
    _send({'type': 'error', 'message': message});
  }

  void _onFeedLevel(double level) {
    final now = DateTime.now();
    if (now.difference(_lastLevelAt).inMilliseconds < 1000) return;
    _lastLevelAt = now;
    _log('level: ${level.toStringAsFixed(1)} dB');
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
    await _feed.stop();
    if (!_listeningWanted || _ws == null || _closed) return;
    await _startListening(_activeLocaleId);
  }

  void _onServerClosed() {
    if (_closed) return;
    _log('сервер закрыл соединение');
    _listeningWanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    unawaited(WakelockPlus.disable());
    _ws = null;
    unawaited(_feed.stop());
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = 'Компьютер отключился';
      _lastPhrase = '';
      _songLines = null;
      _songPos = null;
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
    unawaited(WakelockPlus.disable());
    await _feed.stop();
    await _dropSocket();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _status = '';
      _sttStatus = '';
      _lastPhrase = '';
      _songLines = null;
      _songPos = null;
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
          _Phase.connected || _Phase.listening => DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [Tab(text: 'Песня'), Tab(text: 'Услышано')],
                ),
                Expanded(child: TabBarView(children: [_buildSongTab(), _buildHeardTab()])),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
                  child: Row(
                    children: [
                      Icon(
                        _phase == _Phase.listening
                            ? Icons.graphic_eq
                            : Icons.smartphone,
                        size: 20,
                        color:
                            _phase == _Phase.listening
                                ? Colors.green.shade700
                                : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _phase == _Phase.listening
                              ? (_sttStatus.isNotEmpty
                                    ? _sttStatus
                                    : 'Слушаем и передаём')
                              : 'Ждём песню',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Отправить лог',
                        visualDensity: VisualDensity.compact,
                        onPressed: _logLines.isEmpty
                            ? null
                            : () => unawaited(_sendLog()),
                        icon: const Icon(Icons.upload_file),
                      ),
                      IconButton(
                        tooltip: 'Отключиться',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => unawaited(_disconnect()),
                        icon: const Icon(Icons.mic_off),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        },
      ),
    );
  }
}
