import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

  static const int protocolVersion = 1;

  HttpServer? _server;
  WebSocket? _peer;
  int? _port;
  List<String> _ips = const [];

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

  void startListening() => _sendToPeer({'type': 'listen', 'localeId': localeId});

  void stopListening() => _sendToPeer({'type': 'stop'});

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
    _send(ws, {'type': 'hello', 'v': protocolVersion});
    ws.listen(
      (dynamic data) => _onPeerData(ws, data),
      onDone: () => _onPeerGone(ws),
      onError: (Object e) => _onPeerGone(ws),
      cancelOnError: true,
    );
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
      case 'words':
        final text = decoded['text'];
        if (text is String && text.isNotEmpty) onResult?.call(text);
      case 'error':
        final message = decoded['message'];
        if (message is String) onError?.call(message);
    }
  }

  void _onPeerGone(WebSocket ws) {
    if (!identical(ws, _peer)) return;
    _peer = null;
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
