import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [SongRows, PlaylistRows, PlaylistSongRows, SettingRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

AppDatabase? _sharedDb;

AppDatabase appDatabase() {
  return _sharedDb ??= AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'songbook.sqlite'));
      return NativeDatabase.createInBackground(file);
    }),
  );
}
