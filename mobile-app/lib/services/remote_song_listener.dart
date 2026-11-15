import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'song_listen_session.dart';

typedef RemoteSongListenerFactory = RemoteSongListener Function({
  required String? localeId,
  void Function(String words)? onResult,
  void Function(int port, List<String> ips)? onAddresses,
  void Function()? onPeerConnected,
  void Function()? onPeerDisconnected,
  void Function(String message)? onError,
});

class RemoteSongListener implements SongListenSession {
  RemoteSongListener({
    required this.localeId,
    this.onResult,
    this.onAddresses,
    this.onPeerConnected,
    this.onPeerDisconnected,
    this.onError,
    this.pingInterval = const Duration(seconds: 5),
  });

  final String? localeId;
  final void Function(String words)? onResult;
  final void Function(int port, List<String> ips)? onAddresses;
  final void Function()? onPeerConnected;
  final void Function()? onPeerDisconnected;
  final void Function(String message)? onError;
  final Duration? pingInterval;

  static const int protocolVersion = 3;

  HttpServer? _server;
  WebSocket? _peer;
  int? _port;
  List<String> _ips = const [];
  String? _songContent;
  int? _songTranspose;
  int? _songPos;
  String? _clientLogPath;

  int? get port => _port;
  List<String> get ipCandidates => _ips;
  bool get hasPeer => _peer != null;

  @override
  Future<bool> start() async {
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _port = server.port;
      _ips = await candidateIps();
      onAddresses?.call(server.port, _ips);
      server.listen(
        _onHttpRequest,
        onError: (Object e) => debugPrint('REMOTE server error: $e'),
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      debugPrint('REMOTE bind failed: $e');
      return false;
    }
  }

  void startListening({String? localeId}) =>
      _sendToPeer({'type': 'listen', 'localeId': localeId ?? this.localeId});

  void stopListening() => _sendToPeer({'type': 'stop'});

  void broadcastSong(String? content, {int? transpose, int? pos}) {
    _songContent = content;
    _songTranspose = transpose;
    _songPos = pos;
    _sendToPeer({
      'type': 'song',
      'content': content,
      'transpose': transpose,
      'pos': pos,
    });
  }

  void broadcastPos(int? pos) {
    _songPos = pos;
    _sendToPeer({'type': 'pos', 'pos': pos});
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    _ips = const [];
    final peer = _peer;
    _peer = null;
    if (peer != null) {
      _send(peer, {'type': 'stop'});
      try {
        await peer.close();
      } catch (_) {}
    }
    if (server != null) {
      try {
        await server.close();
      } catch (_) {}
    }
  }

  @override
  void note(String tag) => debugPrint('REMOTE note: $tag');

  void _onHttpRequest(HttpRequest request) async {
    if (request.method == 'POST' && request.uri.path == '/log') {
      await _acceptClientLog(request);
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e) {
      debugPrint('REMOTE upgrade failed: $e');
      return;
    }
    ws.pingInterval = pingInterval;
    final peer = _peer;
    if (peer != null && peer.readyState == WebSocket.open) {
      _send(ws, {'type': 'rejected'});
      try {
        await ws.close();
      } catch (_) {}
      return;
    }
    _peer = ws;
    _clientLogPath = null;
    _send(ws, {'type': 'hello', 'v': protocolVersion});
    ws.listen(
      (dynamic data) => _onPeerData(ws, data),
      onDone: () => _onPeerGone(ws),
      onError: (Object e) => _onPeerGone(ws),
      cancelOnError: true,
    );
  }

  Future<void> _acceptClientLog(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final base = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(base.path, 'logs'));
      logsDir.createSync(recursive: true);
      final name = 'remote-mic.${_stamp(DateTime.now())}.log';
      File(p.join(logsDir.path, name)).writeAsStringSync(body);
      debugPrint('REMOTE client log saved: $name (${body.length} bytes)');
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    } catch (e) {
      debugPrint('REMOTE client log save failed: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  String _stamp(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    String p3(int v) => v.toString().padLeft(3, '0');
    return '${p2(t.year % 100)}-${p2(t.month)}-${p2(t.day)}-'
        '${p2(t.hour)}-${p2(t.minute)}-${p2(t.second)}.${p3(t.millisecond)}';
  }

  void _onPeerData(WebSocket ws, dynamic data) {
    if (!identical(ws, _peer)) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data as String);
    } catch (e) {
      debugPrint('REMOTE bad frame: $e');
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'ready':
        onPeerConnected?.call();
        final content = _songContent;
        if (content != null) {
          _send(ws, {
            'type': 'song',
            'content': content,
            'transpose': _songTranspose,
            'pos': _songPos,
          });
        }
      case 'words':
        final text = decoded['text'];
        if (text is String && text.isNotEmpty) onResult?.call(text);
      case 'error':
        final message = decoded['message'];
        if (message is String) onError?.call(message);
      case 'log':
        final line = decoded['line'];
        if (line is String && line.isNotEmpty) {
          unawaited(_appendClientLog(line));
        }
    }
  }

  Future<void> _appendClientLog(String line) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(base.path, 'logs'));
      logsDir.createSync(recursive: true);
      final path = _clientLogPath ??= p.join(
        logsDir.path,
        'remote-mic.${_stamp(DateTime.now())}.log',
      );
      File(path).writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('REMOTE client log append failed: $e');
    }
  }

  void _onPeerGone(WebSocket ws) {
    if (!identical(ws, _peer)) return;
    _peer = null;
    _clientLogPath = null;
    onPeerDisconnected?.call();
  }

  void _sendToPeer(Map<String, Object?> message) {
    final peer = _peer;
    if (peer == null || peer.readyState != WebSocket.open) return;
    _send(peer, message);
  }

  void _send(WebSocket ws, Map<String, Object?> message) {
    try {
      ws.add(jsonEncode(message));
    } catch (e) {
      debugPrint('REMOTE send failed: $e');
    }
  }

  static Future<List<String>> candidateIps() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final entries = <({int tier, int privacy, String name, String ip})>[];
    for (final nic in interfaces) {
      for (final addr in nic.addresses) {
        entries.add((
          tier: interfaceTier(nic.name),
          privacy: isPrivateV4(addr.address) ? 0 : 1,
          name: nic.name,
          ip: addr.address,
        ));
      }
    }
    entries.sort((a, b) {
      final byTier = a.tier.compareTo(b.tier);
      if (byTier != 0) return byTier;
      final byPrivacy = a.privacy.compareTo(b.privacy);
      if (byPrivacy != 0) return byPrivacy;
      return a.name.compareTo(b.name);
    });
    return entries.map((e) => e.ip).toList();
  }

  static int interfaceTier(String name) {
    if (name.startsWith('en')) return 0;
    if (name.startsWith('utun') ||
        name.startsWith('vmnet') ||
        name.startsWith('tap') ||
        name.startsWith('bridge')) {
      return 2;
    }
    return 1;
  }

  static bool isPrivateV4(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    return false;
  }
}
