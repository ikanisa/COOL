import 'dart:convert';

import '../database/cool_database.dart';
import 'key_value_store.dart';

/// [KeyValueStore] implementation backed by a Drift key-value table.
///
/// Works with any Drift table that has `key TEXT PRIMARY KEY, value TEXT`
/// columns (e.g. [MomoSyncState], [AppPreferences], [FcmPreferences]).
///
/// Values are JSON-encoded for storage and decoded on read, supporting
/// [String], [bool], [int], [double], and [Map]/[List] types.
class DriftKeyValueStore<T> implements KeyValueStore<T> {
  DriftKeyValueStore({required this.db, required this.tableName});

  /// The underlying Drift database.
  final CoolDatabase db;

  /// The table name to read/write from (e.g. 'app_preferences').
  final String tableName;

  // ── Helpers ───────────────────────────────────────────────────

  _KvTable get _table => switch (tableName) {
    'momo_sync_state' => _KvTable.momoSyncState,
    'app_preferences' => _KvTable.appPreferences,
    'fcm_preferences' => _KvTable.fcmPreferences,
    _ => throw ArgumentError.value(
      tableName,
      'tableName',
      'Unsupported Drift key-value table.',
    ),
  };

  String _encode(T value) => jsonEncode(value);

  T _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is T) return decoded;
    // Handle bool stored as JSON (jsonDecode returns bool for "true"/"false").
    return decoded as T;
  }

  // ── KeyValueStore<T> ─────────────────────────────────────────

  @override
  Future<T?> get(String key) async {
    final raw = await (switch (_table) {
      _KvTable.momoSyncState => (() async {
        final row = await (db.select(
          db.momoSyncState,
        )..where((table) => table.key.equals(key))).getSingleOrNull();
        return row?.value;
      })(),
      _KvTable.appPreferences => (() async {
        final row = await (db.select(
          db.appPreferences,
        )..where((table) => table.key.equals(key))).getSingleOrNull();
        return row?.value;
      })(),
      _KvTable.fcmPreferences => (() async {
        final row = await (db.select(
          db.fcmPreferences,
        )..where((table) => table.key.equals(key))).getSingleOrNull();
        return row?.value;
      })(),
    });

    return raw == null ? null : _decode(raw);
  }

  @override
  Future<void> put(String key, T value) async {
    final encoded = _encode(value);
    await (switch (_table) {
      _KvTable.momoSyncState =>
        db
            .into(db.momoSyncState)
            .insertOnConflictUpdate(
              MomoSyncStateCompanion.insert(key: key, value: encoded),
            ),
      _KvTable.appPreferences =>
        db
            .into(db.appPreferences)
            .insertOnConflictUpdate(
              AppPreferencesCompanion.insert(key: key, value: encoded),
            ),
      _KvTable.fcmPreferences =>
        db
            .into(db.fcmPreferences)
            .insertOnConflictUpdate(
              FcmPreferencesCompanion.insert(key: key, value: encoded),
            ),
    });
  }

  @override
  Future<void> delete(String key) async {
    await (switch (_table) {
      _KvTable.momoSyncState => (db.delete(
        db.momoSyncState,
      )..where((table) => table.key.equals(key))).go(),
      _KvTable.appPreferences => (db.delete(
        db.appPreferences,
      )..where((table) => table.key.equals(key))).go(),
      _KvTable.fcmPreferences => (db.delete(
        db.fcmPreferences,
      )..where((table) => table.key.equals(key))).go(),
    });
  }

  @override
  Future<Map<String, T>> getAll() async {
    final entries = await (switch (_table) {
      _KvTable.momoSyncState => (() async {
        final rows = await db.select(db.momoSyncState).get();
        return rows.map((row) => MapEntry(row.key, row.value));
      })(),
      _KvTable.appPreferences => (() async {
        final rows = await db.select(db.appPreferences).get();
        return rows.map((row) => MapEntry(row.key, row.value));
      })(),
      _KvTable.fcmPreferences => (() async {
        final rows = await db.select(db.fcmPreferences).get();
        return rows.map((row) => MapEntry(row.key, row.value));
      })(),
    });

    return {for (final entry in entries) entry.key: _decode(entry.value)};
  }

  @override
  Future<void> clear() async {
    await (switch (_table) {
      _KvTable.momoSyncState => db.delete(db.momoSyncState).go(),
      _KvTable.appPreferences => db.delete(db.appPreferences).go(),
      _KvTable.fcmPreferences => db.delete(db.fcmPreferences).go(),
    });
  }

  @override
  Future<bool> containsKey(String key) async {
    return await get(key) != null;
  }
}

enum _KvTable { momoSyncState, appPreferences, fcmPreferences }
