import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/remote_mic_screen.dart';
import '../services/remote_mic_session.dart';
import 'remote_mic_qr_panel.dart';

Future<void> showRemoteMicDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _RemoteMicDialog(),
  );
}

class _RemoteMicDialog extends StatelessWidget {
  const _RemoteMicDialog();

  @override
  Widget build(BuildContext context) {
    final session = RemoteMicSession.instance;
    return AlertDialog(
      title: const Text('Микрофон'),
      content: AnimatedBuilder(
        animation: session,
        builder: (_, _) {
          if (!session.isEnabled) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.cast),
                  title: const Text('Показываю я'),
                  subtitle: const Text('поёт кто-то другой'),
                  onTap: () {
                    session.lastRole = RemoteMicRole.host;
                    unawaited(session.enable());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic),
                  title: const Text('Пою я'),
                  subtitle: const Text('показывает кто-то другой'),
                  onTap: () {
                    session.lastRole = RemoteMicRole.singer;
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RemoteMicScreen(),
                      ),
                    );
                  },
                ),
              ],
            );
          }
          if (session.isPaired) {
            return const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link, color: Colors.green),
                SizedBox(height: 8),
                Text('Микрофон в паре'),
              ],
            );
          }
          return RemoteMicQrPanel(port: session.port ?? 0, ips: session.ips);
        },
      ),
      actions: [
        if (session.isEnabled)
          TextButton(
            onPressed: () => unawaited(session.disable()),
            child: const Text('Отключить'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
