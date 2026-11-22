# Переезд на drift: план реализации

> **For agentic workers:** циклы по скиллу csharp-unit-test (test → Red → code → Green → review → discussion), один тест за цикл, ревью после каждого.

**Goal:** Локальное хранение на drift (SQLite, натив) **без смены интерфейсов**: `SongStorage`/`TagStore` остаются как есть, реализации переезжают на drift, `fileName` семантически становится guid. Веб отрезан.

**Architecture:** `AppDatabase` (drift, NativeDatabase/ffi, singleton). `DriftSongStorage`/`DriftTagStore` за существующими интерфейсами; контент песни хранится сырым текстом (с шапками), парсинг — `Song.fromRaw` как сейчас. guid при сохранении не меняется → ренейм-цепочка редактора не срабатывает, тэги переживают ренейм тривиально. Шрифт — глобальная настройка (`Settings`), per-song `fontSize` из модели уходит.

**Tech Stack:** drift 2.35.4 + drift_dev + build_runner, sqlite3_flutter_libs, uuid. Тесты: `NativeDatabase.memory()`.

**Spec:** дизайн согласован в обсуждении (сессия 22 ноя): интерфесы не трогаем, fileName=guid, шрифт глобальный, веб отрезан (вариант 3), переименование fileName→id — отдельный заход после всего.

## Global Constraints

- Пакет `song_book`, команды — `mobile-app/`, SDK — `fvm flutter` (3.47.6).
- Без комментариев в коде, кроме исключения: в drift-сторах одна пометка «fileName на самом деле guid» (историческое имя, неочевидно).
- UI-строки на русском.
- Guid — текстовый uuid v4; при updateSong гуид не меняется.
- Схема зеркалит серверную из `postponed/client-server-plan.md`: `deletedAt`-колонки и `position` есть, не используются до синка. SQL-имена: `song`, `playlist`, `playlist_song`, `setting`.
- `shared_preferences` остаётся только для DeepSeek-ключей и карты тэгов legacy-импорта.

## Review Focus

1. Импорт с непарсируемым телом файла не роняет миграцию — файл становится песней целиком.
2. Повторный запуск импорта (каталог уже в `songs.imported`) не дублирует песни.
3. setTags пустым списком удаляет плейлист и связки, не оставляя мусора.
4. deleteSong чистит строки playlist_song.
5. Песня без тэгов и тэг без песен не создают записей.
6. Пустая БД + пустой каталог → сид примера.

---

### Task 1: DriftTagStore (интерфейс TagStore, реализация на drift)

**Files:** Create `mobile-app/lib/services/drift_tag_store.dart`; Modify `tag_store.dart` (интерфейс + фабрика), `test/tag_store_test.dart` (перевод на drift).

- Конструктор `DriftTagStore(AppDatabase)`; тесты — на изолированном `NativeDatabase.memory()`.
- Методы: `all` (Map guid→тэги), `allTags` (объединение, сорт по lower), `tagsOf` ([] при отсутствии), `setTags` (нормализация: trim, пустые вон, дедуп, сорт; пустой список удаляет плейлист+связки), `renameTag` (замена по всем, коллизия мержится), `deleteTag` (снять со всех, чистить пустые), `deleteSong` (чистка связок), `renameSong` (no-op: guid не меняется).
- Существующие 19 тестов tag_store_test переводятся на drift (сетап: пустая БД или сид строками напрямую), добавляются тесты чистки связок.

### Task 2: DriftSongStorage (интерфейс SongStorage, реализация на drift)

**Files:** Create `mobile-app/lib/services/drift_song_storage.dart`; Modify `song_storage.dart` (фабрика), `test/drift_song_storage_test.dart` (новый).

- `listSongs`: все строки `song` (deletedAt IS NULL), `Song.fromRaw(fileName: id, rawContent: content)`, сорт по title (lower).
- `writeSong`: нет `oldFileName` → новый uuid-гайд, вставка; есть → update строки `id = oldFileName`, возвращает тот же guid.
- `deleteSong`: удаление строки; связки чистит `DriftTagStore.deleteSong` (уже вызывается из home_screen).
- `seedIfFirstRun`: БД пуста и каталог `songs/` пуст/нет → сид примера; иначе импорт: каждый `.txt` → строка (guid, raw content как есть), карта `tags_data` из prefs → плейлисты+связки по guid; каталог → `songs.imported` (занято — `.imported.2`); битый файл не роняет импорт; повторный запуск — no-op (каталога нет).

### Task 3: Глобальный шрифт + заводим фабрики + чистка

**Files:** Create `mobile-app/lib/services/font_size_store.dart`; Modify `song_detail_screen.dart`, `models/song.dart` (без fontSize), фабрики в `song_storage.dart`/`tag_store.dart` → drift, `main.dart`/`home_screen.dart` (kIsWeb → WebUnsupportedScreen); Delete `file_song_store.dart`, `prefs_song_store.dart`, старая prefs-реализация TagStore.

- `FontSizeStore`: `get()`/`set()` на `setting` (ключ `fontSize`, default 20), конструируется как соседние сторы.
- Кнопки шрифта экрана песни → `FontSizeStore`; `defaultFontSize` остаётся константой-дефолтом.
- Прогон всего suite.

### Task 4: fileName → id (отдельный заход)

**Files:** Механическое переименование по всему пакету: поле/параметры/переменные `fileName` → `id`, тесты включительно.

- Переименование без изменения поведения; suite зелёный; коммит отдельный.
