import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/deepseek_credentials.dart';
import '../services/song_finder.dart';

/// Результат генерации: заголовок (исходный запрос) + текст песни с аккордами.
typedef SongDraft = ({String title, String content});

/// Ищет песню в интернете и форматирует разбор через DeepSeek.
class DeepSeekSongScreen extends StatefulWidget {
  final String query;
  const DeepSeekSongScreen({super.key, required this.query});

  @override
  State<DeepSeekSongScreen> createState() => _DeepSeekSongScreenState();
}

class _DeepSeekSongScreenState extends State<DeepSeekSongScreen> {
  late Future<FoundSong> _future;
  FoundSong? _found;

  @override
  void initState() {
    super.initState();
    _kickOff();
  }

  Future<FoundSong> _find() async {
    final key = await DeepSeekCredentials.readApiKey();
    return SongFinder(key).find(widget.query);
  }

  void _kickOff() {
    // _future присваивается синхронно — иначе первый build успеет прочитать
    // неинициализированное late-поле.
    _future = _find();
    _future
        .then((v) {
          if (mounted) setState(() => _found = v);
        })
        .catchError((_) {});
  }

  void _retry() {
    setState(() => _found = null);
    _kickOff();
  }

  Future<void> _save() async {
    final found = _found;
    if (found == null || found.content.trim().isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pop(
      (title: widget.query, content: found.content),
    );
  }

  /// Открывает чат DeepSeek в браузере (для ручной проверки).
  Future<void> _openChat() async {
    await launchUrl(
      Uri.parse(
          'https://chat.deepseek.com/?q=${Uri.encodeQueryComponent(widget.query)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final responseText = (_found?.content ?? '').trim();
    final isRefusal = responseText.length < 60 &&
        responseText.toLowerCase().contains('не найдено');
    final ready = responseText.isNotEmpty && !isRefusal;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.query, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<FoundSong>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _Generating();
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _retry,
            );
          }
          final found = snapshot.data!;
          final text = found.content.trim().isEmpty
              ? '(пустой ответ)'
              : found.content;
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: scheme.primaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 18, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Разбор собран из интернета и оформлен ИИ (DeepSeek). '
                        'Аккорды могут содержать ошибки — проверяйте перед '
                        'сохранением.',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RequestDebug(
                        found.requestDebug,
                        sources: found.sourceHosts,
                        onOpenChat: _openChat,
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'Roboto Mono',
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: ready ? _save : null,
            icon: const Icon(Icons.save_alt),
            label: const Text('Сохранить в песенник'),
          ),
        ),
      ),
    );
  }
}

/// Отладочный блок: источники и запрос к DeepSeek (ключ замаскирован).
class _RequestDebug extends StatelessWidget {
  final String text;
  final List<String> sources;
  final VoidCallback onOpenChat;
  const _RequestDebug(this.text,
      {required this.sources, required this.onOpenChat});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Запрос к DeepSeek:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Чат'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Источники: ${sources.join(', ')}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: const TextStyle(fontFamily: 'Roboto Mono', fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Generating extends StatelessWidget {
  const _Generating();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Ищу песню и собираю разбор…',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          const Text(
            'Поиск + загрузка страниц + ИИ — это может занять до минуты',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Не получилось',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
