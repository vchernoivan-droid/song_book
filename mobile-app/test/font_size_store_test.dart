import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/db/database.dart';
import 'package:song_book/services/font_size_store.dart';

void main() {
  late AppDatabase db;
  late FontSizeStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = FontSizeStore(db);
  });

  tearDown(() => db.close());

  test('set пишет, get читает', () async {
    await store.set(22);

    expect(await store.get(), 22);
  });

  test('get без настройки — дефолт 20', () async {
    expect(await store.get(), 20);
  });
}
