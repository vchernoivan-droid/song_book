import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:song_book/services/remote_mic_session.dart';
import 'package:song_book/services/remote_song_listener.dart';
import 'package:song_book/widgets/remote_mic_dialog.dart';

class _FakeListener extends RemoteSongListener {
  _FakeListener({
    required super.localeId,
    super.onResult,
    super.onAddresses,
    super.onPeerConnected,
    super.onPeerDisconnected,
  });

  @override
  Future<bool> start() async {
    onAddresses?.call(54321, const ['192.168.1.2']);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  void startListening({String? localeId}) {}
}

void main() {
  testWidgets('лайтбокс: роль хоста показывает QR с адресом сервера', (tester) async {
    final session = RemoteMicSession(
      factory: ({required localeId, onResult, onAddresses, onPeerConnected, onPeerDisconnected, onError}) =>
          _FakeListener(
            localeId: localeId,
            onResult: onResult,
            onAddresses: onAddresses,
            onPeerConnected: onPeerConnected,
            onPeerDisconnected: onPeerDisconnected,
          ),
    );
    addTearDown(() => session.disable());

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () =>
                  unawaited(showRemoteMicDialog(context, session: session)),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Показываю я'), findsOneWidget);

    await tester.tap(find.text('Показываю я'));
    await tester.pumpAndSettle();

    expect(session.isEnabled, isTrue);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(QrImageView), paints..rect());
    expect(find.text('ws://192.168.1.2:54321'), findsOneWidget);
  });
}
