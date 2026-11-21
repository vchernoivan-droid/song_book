import 'package:drift/drift.dart';

class SongRows extends Table {
  @override
  String get tableName => 'song';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get content => text()();
  IntColumn get transpose => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaylistRows extends Table {
  @override
  String get tableName => 'playlist';

  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaylistSongRows extends Table {
  @override
  String get tableName => 'playlist_song';

  TextColumn get playlistId => text()();
  TextColumn get songId => text()();
  IntColumn get position => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {playlistId, songId};
}

class SettingRows extends Table {
  @override
  String get tableName => 'setting';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
