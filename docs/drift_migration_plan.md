# Hive → Drift/SQLite Migration Plan

> **Status:** Draft — ready for review
> **Created:** 2026-04-30
> **Owner:** Architecture team

---

## 1. Motivation

### Why migrate?

| Concern | Hive today | Drift target |
|---------|-----------|--------------|
| **Query capability** | Key-value only; no filtering, joining, or sorting | Full SQL: WHERE, JOIN, ORDER BY, aggregates |
| **Type safety** | Runtime type casts (`box.get('key') as T?`) | Compile-time verified schemas via code-gen |
| **Data integrity** | No transactions, no constraints, no FK enforcement | SQLite ACID transactions, CHECK/FK constraints |
| **Corruption recovery** | Delete-and-recreate (data loss) | WAL mode + rollback journal; point-in-time recovery |
| **Testability** | Requires Hive.init() + temp directories | `NativeDatabase.memory()` — pure in-process |
| **Scalability** | Entire box loaded into RAM | Lazy cursor-based reads; handles 100K+ rows |
| **Maintenance** | Hive is effectively unmaintained (last release 2023) | Drift is actively maintained with Dart 3 support |

### What data is at risk?

All Hive-stored data in COOL is either:
- **Regenerable** from the Supabase backend (sync queue, SMS sync state, BioPay cache)
- **User preference** data (theme, FCM prefs, access flags) that can be defaulted

A migration failure would cause **temporary inconvenience** (re-sync, re-set preferences) but **zero data loss** for business-critical records.

---

## 2. Inventory of Hive Boxes

| # | Box name | Service | Type param | Data stored | Criticality |
|---|----------|---------|------------|-------------|-------------|
| 1 | `sync_engine_queue` | `SyncEngine` | `dynamic` | Pending offline mutations (JSON blobs) | Medium — re-queued on next sync |
| 2 | `momo_sms_sync_state` | `MomoSmsSyncState` | `String` | Last-sync timestamp, cursor | Low — full re-scan recovers |
| 3 | `biopay_match_cache_v1` | `BiopayCacheService` | `dynamic` | Face embedding match results (TTL cache) | Low — pure cache |
| 4 | `app_access_preferences` | `AppAccessService` | `bool` | Onboarding flags, PIN setup status | Low — defaultable |
| 5 | `cool_fcm_prefs` | `FcmService` / support | `dynamic` | FCM token, topic subscriptions | Low — re-registered on start |
| 6 | `theme_preferences` | `ThemePreferenceStore` | `String` | Light/dark mode selection | Low — default to system |
| 7 | `_cool_hive_meta` | `hive_runtime.dart` | `dynamic` | Schema version number | Internal — replaced by Drift versioning |

**Total: 7 boxes, 0 with irreplaceable user data.**

---

## 3. Migration Strategy

### Approach: **Parallel cut-over with adapter layer**

```
Phase A: Introduce Drift (add dependency, create schema, adapter interface)
Phase B: Dual-write (Hive + Drift) behind feature flag for 1 release cycle
Phase C: Read from Drift, stop writing to Hive
Phase D: Remove Hive dependency entirely
```

### Why not big-bang?

- The sync queue and FCM service are write-hot during bootstrap — a broken migration could silently drop offline mutations.
- Dual-write gives us a safety net: if Drift writes fail, Hive is still the fallback reader.
- One release cycle of dual-write provides field validation before removing Hive.

---

## 4. Drift Schema Design

### 4.1 Database file

```dart
// lib/core/database/cool_database.dart

import 'package:drift/drift.dart';

part 'cool_database.g.dart';

class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get payload => text()();            // JSON blob
  TextColumn get table_ => text().named('table_name')();
  TextColumn get operation => text()();          // insert | update | delete
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}

class MomoSyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class AppPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class FcmPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

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
  CoolDatabase(QueryExecutor e) : super(e);

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
```

### 4.2 Provider

```dart
// lib/core/providers/database_provider.dart

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../database/cool_database.dart';

final coolDatabaseProvider = Provider<CoolDatabase>((ref) {
  final db = CoolDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'cool_v1.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

---

## 5. Adapter Interface

Create a storage abstraction so services don't depend on Hive or Drift directly:

```dart
// lib/core/storage/key_value_store.dart

/// Platform-agnostic key-value store interface.
///
/// Implementations:
/// - HiveKeyValueStore (current, deprecated)
/// - DriftKeyValueStore (target)
/// - InMemoryKeyValueStore (testing)
abstract class KeyValueStore<T> {
  Future<T?> get(String key);
  Future<void> put(String key, T value);
  Future<void> delete(String key);
  Future<Map<String, T>> getAll();
  Future<void> clear();
}
```

Each service currently accepting `OpenHiveBox<T>` would instead accept `KeyValueStore<T>`:

| Service | Current param | Migrated param |
|---------|---------------|----------------|
| `SyncEngine` | `OpenHiveBox<dynamic>` | `KeyValueStore<String>` (JSON strings) |
| `MomoSmsSyncState` | `OpenHiveBox<String>` | `KeyValueStore<String>` |
| `AppAccessService` | `OpenHiveBox<bool>` | `KeyValueStore<bool>` (via adapter) |
| `FcmTopicManager` / `FcmTokenPersistor` | `OpenHiveBox<dynamic>` | `KeyValueStore<String>` |
| `ThemePreferenceStore` | `OpenHiveBox<String>` | `KeyValueStore<String>` |
| `BiopayCacheService` | Direct `Hive.openBox` | `BiopayMatchCacheDao` (typed DAO) |

---

## 6. Phased Execution Plan

### Phase A — Foundation (1-2 days)

- [ ] Add `drift`, `drift_dev`, `sqlite3_flutter_libs`, `path_provider`, `path` to `pubspec.yaml`
- [ ] Create `lib/core/database/cool_database.dart` with table definitions
- [ ] Run `dart run build_runner build` to generate `cool_database.g.dart`
- [ ] Create `coolDatabaseProvider` in Riverpod
- [ ] Create `KeyValueStore<T>` abstract interface
- [ ] Create `HiveKeyValueStore<T>` adapter wrapping existing `openHiveBox`
- [ ] Create `DriftKeyValueStore<T>` adapter wrapping Drift tables
- [ ] Create `InMemoryKeyValueStore<T>` for tests
- [ ] Wire `HiveKeyValueStore` as default (no behavior change)
- [ ] **Gate:** `flutter analyze` + `flutter test` — 0 regressions

### Phase B — Dual-Write (2-3 days)

- [ ] Create `DualWriteKeyValueStore<T>` that writes to both Hive and Drift, reads from Hive
- [ ] Swap all services to use `DualWriteKeyValueStore` via Riverpod override
- [ ] Add telemetry: log discrepancies between Hive-read and Drift-read values
- [ ] Ship as v1.3.0-beta with `drift_dualwrite` feature flag (default: on)
- [ ] **Gate:** 7 days of field telemetry showing 0 discrepancies

### Phase C — Cut to Drift (1-2 days)

- [ ] Flip read source from Hive → Drift in `DualWriteKeyValueStore`
- [ ] Stop Hive writes after confirming Drift reads return correct data
- [ ] Replace `DualWriteKeyValueStore` with `DriftKeyValueStore` directly
- [ ] Migrate `BiopayCacheService` to typed DAO (`BiopayMatchCacheDao`)
- [ ] **Gate:** `flutter test` + 3-day field soak with 0 issues

### Phase D — Remove Hive (1 day)

- [ ] Remove `hive_flutter` from `pubspec.yaml`
- [ ] Delete `lib/core/services/hive_runtime.dart`
- [ ] Delete `lib/core/providers/hive_providers.dart`
- [ ] Remove all `OpenHiveBox` typedefs and parameters
- [ ] Delete Hive data on first Drift-only launch (one-time cleanup)
- [ ] **Gate:** `flutter analyze` + `flutter test` — clean build, 0 Hive references

---

## 7. Testing Strategy

| Test layer | Scope | How |
|-----------|-------|-----|
| **Unit** | `KeyValueStore` implementations | `InMemoryKeyValueStore` + `NativeDatabase.memory()` |
| **Unit** | `SyncEngine` with Drift store | Inject `DriftKeyValueStore` backed by in-memory DB |
| **Integration** | Dual-write consistency | Automated comparison of Hive-read vs Drift-read |
| **E2E** | Bootstrap → sync → UI flow | On-device test with real SQLite file |

### Key test cases:

1. **Sync queue recovery:** Enqueue 5 mutations → kill app → restart → all 5 replayed
2. **Theme persistence:** Set dark mode → cold restart → dark mode restored
3. **FCM re-registration:** Token stored → app update → token retrieved correctly
4. **Cache expiry:** BioPay cache entry expires → not returned by DAO
5. **Schema upgrade:** DB at version 1 → app at version 2 → migration runs cleanly

---

## 8. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Drift code-gen build failures | Medium | Low | Pin `drift_dev` version; CI validates `build_runner` |
| SQLite file corruption on device | Low | Medium | WAL mode + integrity check on open; fallback to recreate |
| Data loss during Phase B/C transition | Low | Low | All data regenerable; dual-write provides safety net |
| Increased APK/IPA size from `sqlite3_flutter_libs` | Medium | Low | ~1.2 MB increase; acceptable for production app |
| Build time increase from code-gen | Medium | Low | Scope code-gen to `lib/core/database/` only |

---

## 9. Rollback Plan

- **Phase A:** Revert `pubspec.yaml` and delete `lib/core/database/`. Zero impact on existing behavior.
- **Phase B:** Disable `drift_dualwrite` flag → revert to Hive-only path. No data loss.
- **Phase C:** If Drift reads fail, re-enable Hive reads via the adapter interface. One config change.
- **Phase D:** Cannot easily roll back after Hive removal. This phase should only execute after 2+ weeks of successful Phase C field telemetry.

---

## 10. Dependencies & Versions

```yaml
# pubspec.yaml additions
dependencies:
  drift: ^2.22.0
  sqlite3_flutter_libs: ^0.5.28
  path_provider: ^2.1.5   # already present
  path: ^1.9.0             # already present

dev_dependencies:
  drift_dev: ^2.22.0
  build_runner: ^2.4.0     # may already be present
```

---

## 11. Success Criteria

The migration is **complete** when:

1. ✅ Zero references to `hive_flutter` in `pubspec.yaml`
2. ✅ Zero imports of `package:hive` in `lib/`
3. ✅ All 7 box equivalents operate on Drift/SQLite
4. ✅ `flutter analyze --fatal-infos` — 0 issues
5. ✅ `flutter test` — all pass
6. ✅ 14-day field soak with 0 storage-related crashes in Crashlytics
7. ✅ Sync queue, theme, FCM, and BioPay cache function identically to pre-migration behavior
