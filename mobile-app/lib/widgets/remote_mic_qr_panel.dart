import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RemoteMicQrPanel extends StatelessWidget {
  const RemoteMicQrPanel({super.key, required this.port, required this.ips});

  final int port;
  final List<String> ips;

  @override
  Widget build(BuildContext context) {
    final qr = jsonEncode({'port': port, 'ips': ips});
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        QrImageView(
          data: qr,
          version: QrVersions.auto,
          size: 132,
          padding: const EdgeInsets.all(4),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ожидание телефона',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Откройте на телефоне «Пою я» и наведите камеру на QR',
              ),
              const SizedBox(height: 8),
              for (final ip in ips)
                Text(
                  'ws://$ip:$port',
                  style: TextStyle(
                    fontFamily: 'Roboto Mono',
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
