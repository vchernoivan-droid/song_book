import 'package:drift/drift.dart';

import '../db/database.dart';

class FontSizeStore {
  final AppDatabase db;

  FontSizeStore(this.db);

  static const _key = 'fontSize';
  static const _default = 20;

  Future<int> get() async {
    final row = await (db.select(db.settingRows)
          ..where((s) => s.key.equals(_key)))
        .getSingleOrNull();
    return row == null ? _default : int.parse(row.value);
  }

  Future<void> set(int value) async {
    await db.into(db.settingRows).insert(
          SettingRowsCompanion.insert(key: _key, value: value.toString()),
          onConflict: DoUpdate((_) => SettingRowsCompanion(
                value: Value(value.toString()),
              )),
        );
  }
}
