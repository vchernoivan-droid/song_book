# Переезд хранения на drift — состояние задачи

План: `docs/plans/2026-11-22-drift-migration.md` (закреплён в git). WIP-патч: полка `drift_migration_wip_`.

## Суть решения

- Интерфейсы `SongStorage`/`TagStore` не меняем, реализации переезжают на drift.
- `fileName` семантически стал guid (uuid v4, текст); ренейм-цепочка упразднена (`renameSong` удалён из интерфейса, тэги неприкосновенны при смене названия).
- Схема = серверная из клиент-серверного плана: `song`, `playlist`, `playlist_song`, `setting` (drift-классы `SongRows`/`PlaylistRows`/`PlaylistSongRows`/`SettingRows` + `tableName` в единственном числе; датаклассы `SongRow`…).
- `deletedAt` × 3 и `position` — задел под синк, локально не используются.
- Контент хранится сырым телом без шапок; `transpose` — колонка (пишется напрямую в SQLite, парсинга шапок в drift-мире нет).
- Шрифт — глобальная настройка устройства (`setting.fontSize`), per-song `fontSize` из модели уходит (Task 3).
- Сид примера убран: пустая БД — пустой главный экран.
- Веб отрезан (вариант 3); drift через wasm — отдельная задача, если платформа понадобится.
- Тэги = плейлисты: карта `guid → [тэги]`, тэг живёт пока висит на песне, осиротевшие плейлисты чистятся.

## Сделано (коммиты)

- `1c81794` — схема БД (4 таблицы, drift 2.35.4, тесты на `NativeDatabase.memory()`).
- `6b4a034` — синглтон `appDatabase()` (LazyDatabase, `songbook.sqlite`).
- `1238d3d` — `DriftTagStore` (18 тестов), интерфейс без `renameSong`, редактор без ренейм-цепочки.
- `0f6b74e` — `DriftSongStorage`: listSongs (сорт по title lower), writeSong (create = новый guid / update = тот же), deleteSong, `seedIfFirstRun` = legacy-импорт: `.txt` из `songs/` → строки (transpose из шапки, тело чистое), тэги из prefs `tags_data` → плейлисты (переиспользует `DriftTagStore.setTags`), каталог → `songs.imported`, битые файлы пропускаются, повтор — no-dup.

## В полёте — Task 3 (WIP на полке)

1. `FontSizeStore` — готов и принят (get дефолт 20, set/get upsert); файлы `font_size_store.dart` + тест лежат untracked в дереве.
2. Дальше: `TransposeStore` (get/set колонки по id — кнопки полутонов на экране песни пишут напрямую).
3. Переключить фабрики: `TagStore()` → `DriftTagStore(appDatabase())`, `SongStorage()` → `DriftSongStorage(appDatabase())`.
4. Отрезать веб: `kIsWeb` → `WebUnsupportedScreen` («Работает в приложении»).
5. Кнопки шрифта экрана песни → `FontSizeStore` (глобальный), `Song` модель без `fontSize`.
6. Чистка: `file_song_store.dart`, `prefs_song_store.dart`, prefs-реализация внутри `tag_store.dart`, `example_song.dart`; проверить, что `DeepSeekCredentials` живёт на prefs и не пострадал.

## После — Task 4, 5

- Task 4: механическое переименование `fileName` → `id` по всему пакету (отдельный коммит).
- Task 5: пустой главный экран — без песен нет строки поиска, путь к DeepSeek только через создание пустой песни.

## Грабли среды

- Flutter только через `fvm flutter` (3.47.6, `.fvmrc`); системный 3.41.4 не резолвит зависимости (wakelock_plus).
- build_runner иногда отдаёт протухшую схему после переименований — лечится `fvm dart run build_runner clean` + build.
- drift: колонки int — `integer()`, не `int()`; upsert — `onConflict: DoUpdate(...)`; and-условия — оператор `&`.
- Тесты: `NativeDatabase.memory()`, сетапы низкоуровневые (прямые вставки компаньонами / raw SQL), не через методы стора.
