import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deepseek_credentials.dart';

/// Настройка API-ключа DeepSeek: инструкция, поле, «Сохранить» / «Удалить».
class DeepSeekSettingsScreen extends StatefulWidget {
  const DeepSeekSettingsScreen({super.key});

  @override
  State<DeepSeekSettingsScreen> createState() => _DeepSeekSettingsScreenState();
}

class _DeepSeekSettingsScreenState extends State<DeepSeekSettingsScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    _ctrl.text = await DeepSeekCredentials.readApiKey();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DeepSeekCredentials.save(_ctrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ключ сохранён')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await DeepSeekCredentials.clear();
    _ctrl.clear();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ключ удалён')),
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ключ DeepSeek')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Где взять ключ', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        const Text('1. Зарегистрируйтесь и создайте API-ключ:'),
                        InkWell(
                          onTap: () =>
                              _open('https://platform.deepseek.com/api_keys'),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              'platform.deepseek.com/api_keys',
                              style: TextStyle(
                                color: Colors.indigo,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '2. Пополните баланс — запросы платные по токенам '
                          '(очень дёшево).',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ключ хранится только на этом устройстве.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    hintText: 'sk-…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving || _ctrl.text.trim().isEmpty ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Сохранить'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _ctrl.text.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить ключ'),
                ),
              ],
            ),
    );
  }
}
