import 'package:flutter/foundation.dart';

import 'remote_song_listener.dart';

enum RemoteMicRole { host, singer }

enum RemoteMicLink { off, waiting, paired }

class RemoteMicSession extends ChangeNotifier {
  RemoteMicSession({RemoteSongListenerFactory? factory}) : _factory = factory;

  static final RemoteMicSession instance = RemoteMicSession();

  final RemoteSongListenerFactory? _factory;

  RemoteSongListener? _listener;
  RemoteMicLink _link = RemoteMicLink.off;
  int? _port;
  List<String> _ips = const [];

  RemoteMicRole? lastRole;

  void Function(String words)? onResult;
  void Function(String message)? onError;

  RemoteMicLink get link => _link;
  int? get port => _port;
  List<String> get ips => _ips;
  bool get isEnabled => _listener != null;
  bool get isPaired => _link == RemoteMicLink.paired;

  Future<bool> enable() async {
    if (_listener != null) return true;
    final listener = (_factory ?? RemoteSongListener.new)(
      localeId: null,
      onResult: (words) => onResult?.call(words),
      onAddresses: (port, ips) {
        _port = port;
        _ips = ips;
        notifyListeners();
      },
      onPeerConnected: () {
        _link = RemoteMicLink.paired;
        notifyListeners();
      },
      onPeerDisconnected: () {
        _link = RemoteMicLink.waiting;
        notifyListeners();
      },
      onError: (message) => onError?.call(message),
    );
    final ok = await listener.start();
    if (!ok) return false;
    _listener = listener;
    _link = RemoteMicLink.waiting;
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    final listener = _listener;
    _listener = null;
    _link = RemoteMicLink.off;
    _port = null;
    _ips = const [];
    onResult = null;
    onError = null;
    notifyListeners();
    await listener?.stop();
  }

  void startListening(String? localeId) =>
      _listener?.startListening(localeId: localeId);

  void stopListening() => _listener?.stopListening();

  void broadcastSong(String? content, {int? transpose, int? pos}) =>
      _listener?.broadcastSong(content, transpose: transpose, pos: pos);

  void broadcastPos(int? pos) => _listener?.broadcastPos(pos);

  void note(String tag) => _listener?.note(tag);
}
