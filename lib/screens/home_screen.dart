import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/browser_launcher.dart';
import '../services/deepseek_credentials.dart';
import '../services/song_storage.dart';
import 'deepseek_settings_screen.dart';
import 'deepseek_song_screen.dart';
import 'song_detail_screen.dart';
import 'song_editor_screen.dart';

/// Главный экран: список песен.
///
/// Сверху — закреплённая строка-заголовок (поиск + «Добавить»),
/// реализованная как [ListTile], чтобы её иконки выравнивались с
/// иконками строк песен автоматически.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = SongStorage();
  final _searchCtrl = TextEditingController();

  List<SongWithPreview> _songs = [];
  bool _loading = true;
  bool _deepseekConfigured = false;

  /// Текущий поисковый запрос (сырой, как в поле).
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _storage.seedIfFirstRun();
    final songs = await _storage.listSongs();
    final ds = await DeepSeekCredentials.isConfigured();
    if (!mounted) return;
    setState(() {
      _songs = songs
          .map((x) => SongWithPreview(preview: x.preview, song: x))
          .toList();
      _loading = false;
      _deepseekConfigured = ds;
    });
  }

  String get _q => _query.toLowerCase().trim();

  List<SongWithPreview> get _filtered {
    if (_q.isEmpty) {
      return _songs;
    }
    final rx = RegExp("^([^\n]*${RegExp.escape(_q)}[^\n]*)\$", multiLine: true);
    return _songs
        .map((x) {
          var match = rx.firstMatch(x.song.content.toLowerCase());
          return SongWithPreview(
            song: x.song,
            preview: match == null
                ? null
                : x.song.content.substring(match.start, match.end),
          );
        })
        .where((x) => x.preview != null)
        .toList();
  }

  Future<void> _openEditor([Song? song]) async {
    await Navigator.of(context).push<Song?>(
      MaterialPageRoute(builder: (_) => SongEditorScreen(song: song)),
    );
    _load();
  }

  Future<void> _openSong(Song song) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SongDetailScreen(song: song)));
    // На случай, если песню изменили или удалили на экране просмотра.
    _load();
  }

  Future<bool?> _confirmDelete(Song song) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить песню?'),
        content: Text('«${song.title}» будет удалена безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  /// Очистить текст запроса.
  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  /// Локально ничего не нашлось.
  /// На нативе — генерируем текст через DeepSeek, на вебе — открываем Google.
  Future<void> _openSearch() async {
    final q = _query.trim();
    if (q.isEmpty) return;
    if (kIsWeb) {
      // Веб: к API DeepSeek из браузера не достучаться (CORS) — открываем чат.
      openDeepSeekInTab(q);
      return;
    }
    final draft = await Navigator.of(context).push<SongDraft>(
      MaterialPageRoute(builder: (_) => DeepSeekSongScreen(query: q)),
    );
    if (!mounted || draft == null) return;
    await Navigator.of(context).push<Song?>(
      MaterialPageRoute(
        builder: (_) => SongEditorScreen(
          prefillTitle: draft.title,
          prefillContent: draft.content,
        ),
      ),
    );
    _load();
  }

  /// Экран настройки API-ключа DeepSeek.
  Future<void> _openDeepSeekSetup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const DeepSeekSettingsScreen()),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _songs.isEmpty
            ? _EmptyView(onAdd: () => _openEditor())
            : Column(
                children: [
                  _buildHeader(),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? _NoResultsView(
                            query: _query,
                            onClear: _clearSearch,
                            configured: _deepseekConfigured,
                            onSearch: _openSearch,
                            onEditKey: _openDeepSeekSetup,
                          )
                        : _buildSongsList(filtered),
                  ),
                ],
              ),
      ),
    );
  }

  /// Закреплённая сверху строка: поле поиска (title) + «Добавить» (trailing).
  /// Это [ListTile] — поэтому ведущая/завершающая иконки встают в те же
  /// позиции, что и в строках песен.
  Widget _buildHeader() {
    return ListTile(
      leading: const Icon(Icons.search),
      title: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Поиск по названию или тексту',
          suffixIcon: Visibility(
            visible: _searchCtrl.text.isNotEmpty,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(
              tooltip: 'Очистить',
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            ),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      trailing: IconButton(
        tooltip: 'Добавить',
        icon: const Icon(Icons.add),
        onPressed: () => _openEditor(),
      ),
    );
  }

  Widget _buildSongsList(List<SongWithPreview> filtered) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = filtered[index];
          return Dismissible(
            key: ValueKey(item.song.fileName),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _confirmDelete(item.song),
            onDismissed: (_) async {
              setState(() => _songs.remove(item));
              await _storage.deleteSong(item.song.fileName);
            },
            child: ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: Text(
                item.song.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              subtitle: item.preview == null
                  ? null
                  : Text(
                      item.preview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => _openSong(item.song),
              trailing: IconButton(
                tooltip: 'Открыть',
                icon: const Icon(Icons.arrow_forward_ios_rounded),
                iconSize: 20,
                onPressed: () => _openSong(item.song),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Список песен пуст.
class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Пока пусто',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте свою первую песню\nс аккордами и табами.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }
}

/// По запросу ничего не найдено.
class _NoResultsView extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  final bool configured;
  final VoidCallback onSearch;
  final VoidCallback onEditKey;

  const _NoResultsView({
    required this.query,
    required this.onClear,
    required this.configured,
    required this.onSearch,
    required this.onEditKey,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'По запросу «$query»\nнет совпадений в ваших песнях.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (configured) ...[
              FilledButton.tonalIcon(
                onPressed: onSearch,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Спросить ИИ'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onEditKey,
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('Редактировать ключ'),
              ),
            ] else ...[
              FilledButton.tonalIcon(
                onPressed: onEditKey,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Настроить ключ DeepSeek'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              label: const Text('Сбросить поиск'),
            ),
          ],
        ),
      ),
    );
  }
}
