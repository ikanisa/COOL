/// COOL Platform SQLite database via Drift.
///
/// This replaces the Hive-based storage with a typed, queryable,
/// ACID-compliant SQLite backend. All 7 Hive boxes map to 5 tables.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'cool_database.g.dart';

/// Offline sync queue entries — replaces `sync_engine_queue` Hive box.
class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryId => text()();
  TextColumn get domain => text()();
  TextColumn get payload => text()(); // JSON blob
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
}

/// MoMo SMS sync cursor — replaces `momo_sms_sync_state` Hive box.
class MomoSyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// App-wide preferences — replaces `app_access_preferences` +
/// `theme_preferences` Hive boxes.
class AppPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// FCM token and topic subscriptions — replaces `cool_fcm_prefs` Hive box.
class FcmPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// BioPay face-match result cache — replaces `biopay_match_cache_v1` Hive box.
class BiopayMatchCache extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get resultJson => text()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

@DriftDatabase(tables: [
  SyncQueueEntries,
  MomoSyncState,
  AppPreferences,
  FcmPreferences,
  BiopayMatchCache,
])
class CoolDatabase extends _$CoolDatabase {
  CoolDatabase(super.e);

  /// Named constructor for in-memory testing.
  CoolDatabase.memory()
      : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Future schema migrations go here.
    },
  );
}
