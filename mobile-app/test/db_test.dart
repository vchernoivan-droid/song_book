import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('таблица playlist_song: связь и составной ключ', () async {
    await db.customStatement(
      'INSERT INTO song (id, title, content, updated_at) VALUES (?, ?, ?, ?)',
      ['s-1', 'Тест', 'текст', 1000],
    );
    await db.customStatement(
      'INSERT INTO playlist (id, name, updated_at) VALUES (?, ?, ?)',
      ['p-1', 'Дом', 1000],
    );
    await db.customStatement(
      'INSERT INTO playlist_song (playlist_id, song_id, updated_at) VALUES (?, ?, ?)',
      ['p-1', 's-1', 1000],
    );

    final link = await db.customSelect(
      'SELECT * FROM playlist_song WHERE playlist_id = ? AND song_id = ?',
      variables: [Variable.withString('p-1'), Variable.withString('s-1')],
    ).getSingle();
    expect(link.data['position'], isNull);
    expect(link.data['deleted_at'], isNull);

    expect(
      () => db.customStatement(
        'INSERT INTO playlist_song (playlist_id, song_id, updated_at) VALUES (?, ?, ?)',
        ['p-1', 's-1', 1001],
      ),
      throwsA(anything),
    );
  });

  test('таблица playlists: вставка, дубликат имени запрещён', () async {
    await db.customStatement(
      'INSERT INTO playlist (id, name, updated_at) VALUES (?, ?, ?)',
      ['pl-1', 'Дом', 1000],
    );

    final row = await db.customSelect('SELECT * FROM playlist').getSingle();
    expect(row.data['name'], 'Дом');
    expect(row.data['deleted_at'], isNull);

    expect(
      () => db.customStatement(
        'INSERT INTO playlist (id, name, updated_at) VALUES (?, ?, ?)',
        ['pl-2', 'Дом', 1001],
      ),
      throwsA(anything),
    );
  });

  test('таблица settings: вставка и чтение', () async {
    await db.customStatement(
      'INSERT INTO setting (key, value) VALUES (?, ?)',
      ['fontSize', '22'],
    );

    final row = await db.customSelect(
      'SELECT value FROM setting WHERE key = ?',
      variables: [Variable.withString('fontSize')],
    ).getSingle();
    expect(row.data['value'], '22');
  });

  test('таблица songs: вставка и дефолты', () async {
    await db.customStatement(
      'INSERT INTO song (id, title, content, updated_at) VALUES (?, ?, ?, ?)',
      ['id-1', 'Тест', 'текст', DateTime.now().millisecondsSinceEpoch ~/ 1000],
    );

    final row = await db.customSelect('SELECT * FROM song').getSingle();
    expect(row.data['id'], 'id-1');
    expect(row.data['title'], 'Тест');
    expect(row.data['transpose'], 0);
    expect(row.data['deleted_at'], isNull);
  });
}
