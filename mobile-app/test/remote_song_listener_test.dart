import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_book/services/remote_song_listener.dart';

class _TestClient {
  _TestClient(this.ws) {
    ws.listen(
      (dynamic data) => _onData(data),
      onDone: _closed.complete,
      onError: (Object e) {
        if (!_closed.isCompleted) _closed.complete();
      },
      cancelOnError: true,
    );
  }

  final WebSocket ws;
  final Completer<void> _closed = Completer<void>();
  final List<Map<String, Object?>> _queue = [];
  final List<Completer<Map<String, Object?>>> _waiters = [];

  bool get isClosed => _closed.isCompleted;

  Future<void> get done => _closed.future;

  void _onData(dynamic data) {
    final decoded = jsonDecode(data as String);
    if (decoded is! Map<String, Object?>) return;
    if (_waiters.isEmpty) {
      _queue.add(decoded);
    } else {
      _waiters.removeAt(0).complete(decoded);
    }
  }

  Future<Map<String, Object?>> next() {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    final waiter = Completer<Map<String, Object?>>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void send(Map<String, Object?> message) => ws.add(jsonEncode(message));

  Future<void> close() => ws.close();
}

Future<({WebSocket ws, _TestClient client})> _connect(int port) async {
  final ws = await WebSocket.connect('ws://127.0.0.1:$port');
  return (ws: ws, client: _TestClient(ws));
}

void main() {
  test('start отдаёт порт и адреса, клиент получает hello', () async {
    final addresses = Completer<(int, List<String>)>();
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      onAddresses: (port, ips) => addresses.complete((port, ips)),
      pingInterval: null,
    );
    addTearDown(listener.stop);
    expect(await listener.start(), isTrue);

    final (port, ips) = await addresses.future;
    expect(listener.port, port);
    expect(listener.port, greaterThan(0));
    expect(listener.ipCandidates, ips);

    final c = await _connect(port);
    addTearDown(c.client.close);
    expect(await c.client.next(), {'type': 'hello', 'v': 3});
  });

  test('ready → listen с локалью, words → onResult', () async {
    final connected = Completer<void>();
    final words = Completer<String>();
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      onPeerConnected: connected.complete,
      onResult: words.complete,
      pingInterval: null,
    );
    addTearDown(listener.stop);
    await listener.start();

    final c = await _connect(listener.port!);
    addTearDown(c.client.close);
    await c.client.next();
    expect(listener.hasPeer, isTrue);

    c.client.send({'type': 'ready'});
    await connected.future;
    listener.startListening();
    expect(await c.client.next(), {'type': 'listen', 'localeId': 'ru-RU'});

    c.client.send({'type': 'words', 'text': 'ла ла ла'});
    expect(await words.future, 'ла ла ла');
  });

  test('второе соединение получает rejected и закрывается, первое живо', () async {
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      pingInterval: null,
    );
    addTearDown(listener.stop);
    await listener.start();

    final first = await _connect(listener.port!);
    addTearDown(first.client.close);
    expect(await first.client.next(), {'type': 'hello', 'v': 3});

    final second = await _connect(listener.port!);
    expect(await second.client.next(), {'type': 'rejected'});
    await second.client.done;
    expect(second.client.isClosed, isTrue);

    first.client.send({'type': 'ready'});
    listener.startListening();
    expect(await first.client.next(), {'type': 'listen', 'localeId': 'ru-RU'});
  });

  test('broadcastSong/broadcastPos доезжают до пира и пересылаются после реконнекта', () async {
    final listener = RemoteSongListener(localeId: 'ru-RU', pingInterval: null);
    addTearDown(listener.stop);
    expect(await listener.start(), isTrue);
    final port = listener.port!;

    final c1 = await _connect(port);
    addTearDown(c1.client.close);
    await c1.client.next();
    c1.client.send({'type': 'ready'});
    await pumpEventQueue();

    listener.broadcastSong('Am\nтекст', transpose: 2, pos: null);
    expect(
      await c1.client.next(),
      {'type': 'song', 'content': 'Am\nтекст', 'transpose': 2, 'pos': null},
    );

    listener.broadcastPos(1);
    expect(await c1.client.next(), {'type': 'pos', 'pos': 1});

    listener.broadcastSong(null);
    expect(
      await c1.client.next(),
      {
        'type': 'song',
        'content': null,
        'transpose': null,
        'pos': null,
      },
    );

    listener.broadcastSong('новая', transpose: 0, pos: 0);
    await c1.client.next();
    await c1.client.close();
    await Future<void>.delayed(Duration.zero);

    final c2 = await _connect(port);
    addTearDown(c2.client.close);
    await c2.client.next();
    c2.client.send({'type': 'ready'});
    await pumpEventQueue();
    expect(
      await c2.client.next(),
      {'type': 'song', 'content': 'новая', 'transpose': 0, 'pos': 0},
    );
  });

  test('разрыв соединения → onPeerDisconnected', () async {
    final disconnected = Completer<void>();
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      onPeerDisconnected: disconnected.complete,
      pingInterval: null,
    );
    addTearDown(listener.stop);
    await listener.start();

    final c = await _connect(listener.port!);
    await c.client.next();
    await c.client.close();
    await disconnected.future;
    expect(listener.hasPeer, isFalse);
  });

  test('error от клиента доезжает до onError', () async {
    final errors = Completer<String>();
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      onError: errors.complete,
      pingInterval: null,
    );
    addTearDown(listener.stop);
    await listener.start();

    final c = await _connect(listener.port!);
    addTearDown(c.client.close);
    await c.client.next();
    c.client.send({'type': 'error', 'message': 'микрофон не дали'});
    expect(await errors.future, 'микрофон не дали');
  });

  test('stopListening шлёт stop, stop закрывает сервер', () async {
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      pingInterval: null,
    );
    await listener.start();
    final port = listener.port!;

    final c = await _connect(port);
    await c.client.next();

    listener.stopListening();
    expect(await c.client.next(), {'type': 'stop'});

    await listener.stop();
    await c.client.done;
    expect(c.client.isClosed, isTrue);
    expect(
      () => WebSocket.connect('ws://127.0.0.1:$port'),
      throwsA(anything),
    );
  });

  test('listen уходит после паузы-отсчёта, pingInterval не мешает', () async {
    final connected = Completer<void>();
    final listener = RemoteSongListener(
      localeId: 'ru-RU',
      onPeerConnected: connected.complete,
    );
    addTearDown(listener.stop);
    await listener.start();

    final c = await _connect(listener.port!);
    addTearDown(c.client.close);
    await c.client.next();
    c.client.send({'type': 'ready'});
    await connected.future;
    await Future<void>.delayed(const Duration(seconds: 4));

    listener.startListening();
    expect(await c.client.next(), {'type': 'listen', 'localeId': 'ru-RU'});
  });

  test('POST /log пишет файл в documents/logs и отвечает 200', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final docs = Directory.systemTemp.createTempSync('rmic_log_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return docs.path;
          }
          return null;
        });

    final listener = RemoteSongListener(localeId: 'ru-RU', pingInterval: null);
    await listener.start();

    final body = '11:22:33.444 status: listening';
    final socket = await Socket.connect('127.0.0.1', listener.port!);
    socket.write(
      'POST /log HTTP/1.1\r\nHost: 127.0.0.1\r\n'
      'Content-Type: text/plain\r\nContent-Length: ${body.length}\r\n'
      'Connection: close\r\n\r\n$body',
    );
    final response = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    expect(response, contains(' 200 '));

    final logsDir = Directory(p.join(docs.path, 'logs'));
    final files = logsDir.listSync();
    expect(files, hasLength(1));
    expect(
      (files.single as File).readAsStringSync(),
      contains('status: listening'),
    );
    await listener.stop();
  });
}
