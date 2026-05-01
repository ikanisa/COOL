/// Pending-write sync engine.
///
/// Queues offline writes through a pluggable store and provides a `flush`
/// mechanism that retries with exponential backoff and discards stale entries.
///
/// This is an **explicit** sync engine — callers trigger `flush()`.
/// No background auto-sync. This keeps behavior testable and predictable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../database/cool_database.dart';
import '../utils/app_logger.dart';

import '../services/hive_runtime.dart';
import 'sync_status.dart';

/// A single pending write stored in the Hive queue.
class PendingWrite {
  PendingWrite({
    required this.id,
    required this.domain,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  factory PendingWrite.fromMap(Map<String, dynamic> map) {
    return PendingWrite(
      id: map['id'] as String,
      domain: map['domain'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      createdAt: DateTime.parse(map['created_at'] as String),
      attempts: (map['attempts'] as int?) ?? 0,
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.parse(map['last_attempt_at'] as String)
          : null,
      lastError: map['last_error'] as String?,
    );
  }

  final String id;
  final String domain;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int attempts;
  DateTime? lastAttemptAt;
  String? lastError;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'domain': domain,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'attempts': attempts,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'last_error': lastError,
  };
}

/// Handler function that attempts to sync a single pending write.
///
/// Should throw on failure. On success, return normally.
typedef SyncHandler =
    Future<void> Function(String id, Map<String, dynamic> payload);

const _log = AppLogger('SyncEngine');

final class SyncQueueRawEntry {
  const SyncQueueRawEntry({required this.storageKey, required this.value});

  final Object? storageKey;
  final Object? value;
}

abstract interface class SyncQueueStore {
  Future<List<SyncQueueRawEntry>> readEntries();
  Future<void> put(String storageKey, PendingWrite write);
  Future<void> delete(Object? storageKey);
  Future<bool> isEmpty();
}

final class HiveSyncQueueStore implements SyncQueueStore {
  HiveSyncQueueStore({
    required String boxName,
    required OpenHiveBox<dynamic> openBox,
  }) : _boxName = boxName,
       _openBox = openBox;

  final String _boxName;
  final OpenHiveBox<dynamic> _openBox;

  Future<Box<dynamic>> _box() => _openBox(_boxName);

  @override
  Future<List<SyncQueueRawEntry>> readEntries() async {
    final box = await _box();
    return [
      for (final key in box.keys)
        SyncQueueRawEntry(storageKey: key, value: box.get(key)),
    ];
  }

  @override
  Future<void> put(String storageKey, PendingWrite write) async {
    final box = await _box();
    await box.put(storageKey, write.toMap());
  }

  @override
  Future<void> delete(Object? storageKey) async {
    final box = await _box();
    await box.delete(storageKey);
  }

  @override
  Future<bool> isEmpty() async {
    final box = await _box();
    return box.isEmpty;
  }
}

final class DriftSyncQueueStore implements SyncQueueStore {
  const DriftSyncQueueStore({required this.db});

  final CoolDatabase db;

  @override
  Future<List<SyncQueueRawEntry>> readEntries() async {
    final rows = await db.select(db.syncQueueEntries).get();
    return [
      for (final row in rows)
        SyncQueueRawEntry(
          storageKey: row.entryId,
          value: <String, dynamic>{
            'id': row.entryId,
            'domain': row.domain,
            'payload': _decodePayload(row.payload),
            'created_at': row.createdAt.toIso8601String(),
            'attempts': row.attempts,
            'last_attempt_at': row.lastAttemptAt?.toIso8601String(),
            'last_error': row.lastError,
          },
        ),
    ];
  }

  Object? _decodePayload(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  @override
  Future<void> put(String storageKey, PendingWrite write) async {
    await db.transaction(() async {
      await delete(storageKey);
      await db
          .into(db.syncQueueEntries)
          .insert(
            SyncQueueEntriesCompanion.insert(
              entryId: storageKey,
              domain: write.domain,
              payload: jsonEncode(write.payload),
              createdAt: Value(write.createdAt),
              attempts: Value(write.attempts),
              lastAttemptAt: Value(write.lastAttemptAt),
              lastError: Value(write.lastError),
            ),
          );
    });
  }

  @override
  Future<void> delete(Object? storageKey) async {
    await (db.delete(
          db.syncQueueEntries,
        )..where((table) => table.entryId.equals(storageKey?.toString() ?? '')))
        .go();
  }

  @override
  Future<bool> isEmpty() async {
    final rows = await (db.select(db.syncQueueEntries)..limit(1)).get();
    return rows.isEmpty;
  }
}

/// Central pending-write queue backed by Hive or Drift.
///
/// Usage:
/// ```dart
/// final engine = SyncEngine(openBox: openHiveBox);
/// await engine.enqueue('momo_pending', pendingPayload);
/// final result = await engine.flush('momo_pending', myMomoSyncHandler);
/// ```
class SyncEngine {
  /// Creates a SyncEngine.
  ///
  /// [boxName] — the Hive box used for the pending queue.
  /// [maxAttempts] — max retries before an entry is discarded.
  /// [staleDuration] — entries older than this are discarded.
  /// [openBox] — injectable Hive box opener for testing.
  SyncEngine({
    String boxName = _defaultBoxName,
    this.maxAttempts = 10,
    this.staleDuration = const Duration(hours: 48),
    OpenHiveBox<dynamic>? openBox,
    SyncQueueStore? queueStore,
  }) : _queueStore =
           queueStore ??
           HiveSyncQueueStore(
             boxName: boxName,
             openBox:
                 openBox ??
                 (throw ArgumentError(
                   'Either openBox or queueStore must be provided.',
                 )),
           );

  SyncEngine.drift({
    required CoolDatabase db,
    this.maxAttempts = 10,
    this.staleDuration = const Duration(hours: 48),
  }) : _queueStore = DriftSyncQueueStore(db: db);

  static const _defaultBoxName = 'sync_engine_queue';

  /// Maximum number of sync attempts before discarding.
  final int maxAttempts;

  /// Entries older than this are considered stale and discarded.
  final Duration staleDuration;

  final SyncQueueStore _queueStore;

  /// Current sync engine status for UI consumption.
  final ValueNotifier<SyncEngineStatus> status = ValueNotifier(
    SyncEngineStatus.idle,
  );

  static final Random _random = Random.secure();

  /// Add a pending write to the queue.
  ///
  /// [domain] groups writes by feature (e.g. 'momo_pending', 'contribution').
  /// [payload] is the data to sync when connectivity returns.
  /// [id] is an optional unique identifier; one is generated if omitted.
  Future<String> enqueue(
    String domain,
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final writeId =
        id ??
        '${domain}_${DateTime.now().microsecondsSinceEpoch}_'
            '${_random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

    final write = PendingWrite(
      id: writeId,
      domain: domain,
      payload: payload,
      createdAt: DateTime.now(),
    );

    await _queueStore.put(writeId, write);

    _log.debug('Enqueued $domain/$writeId');
    await _updateStatus();
    return writeId;
  }

  /// Flush all pending writes for a given [domain].
  ///
  /// [handler] is called for each pending item. If it throws, the item's
  /// attempt count is incremented and it stays in the queue (unless max
  /// attempts reached, in which case it is discarded).
  Future<SyncFlushResult> flush(String domain, SyncHandler handler) async {
    final entries = await _queueStore.readEntries();
    final now = DateTime.now();

    var synced = 0;
    var failed = 0;
    var discarded = 0;
    var skippedBackoff = 0;

    status.value = SyncEngineStatus.syncing;

    for (final entry in entries) {
      final rawEntry = entry.value;
      if (rawEntry is! Map) {
        await _queueStore.delete(entry.storageKey);
        discarded++;
        continue;
      }

      PendingWrite write;
      try {
        write = PendingWrite.fromMap(Map<String, dynamic>.from(rawEntry));
      } catch (_) {
        await _queueStore.delete(entry.storageKey);
        discarded++;
        continue;
      }

      // Only process entries for the requested domain.
      if (write.domain != domain) {
        continue;
      }

      // Discard stale entries.
      if (now.difference(write.createdAt) > staleDuration) {
        _log.info('Discarding stale $domain/${write.id}');
        await _queueStore.delete(entry.storageKey);
        discarded++;
        continue;
      }

      // Discard entries that exceeded max attempts.
      if (write.attempts >= maxAttempts) {
        _log.info(
          'Discarding $domain/${write.id} after '
          '${write.attempts} attempts',
        );
        await _queueStore.delete(entry.storageKey);
        discarded++;
        continue;
      }

      // Skip entries in backoff cooldown.
      if (_isInBackoff(write, now)) {
        skippedBackoff++;
        continue;
      }

      // Attempt sync.
      try {
        await handler(write.id, write.payload);
        await _queueStore.delete(entry.storageKey);
        synced++;
        _log.debug('Synced $domain/${write.id}');
      } catch (error) {
        write.attempts++;
        write.lastAttemptAt = now;
        write.lastError = error.toString();
        await _queueStore.put(write.id, write);
        failed++;
        _log.warn(
          'Failed $domain/${write.id} attempt '
          '${write.attempts}: $error',
          error: error,
        );
      }
    }

    await _updateStatus();

    return SyncFlushResult(
      synced: synced,
      failed: failed,
      discarded: discarded,
      skippedBackoff: skippedBackoff,
    );
  }

  /// Returns the number of pending writes for a given [domain].
  Future<int> pendingCount(String domain) async {
    final entries = await _queueStore.readEntries();
    var count = 0;
    for (final entry in entries) {
      final raw = entry.value;
      if (raw is Map && raw['domain'] == domain) {
        count++;
      }
    }
    return count;
  }

  /// Returns all pending writes (for debugging / UI).
  Future<List<PendingWrite>> pendingWrites(String domain) async {
    final entries = await _queueStore.readEntries();
    final result = <PendingWrite>[];
    for (final entry in entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      try {
        final write = PendingWrite.fromMap(Map<String, dynamic>.from(raw));
        if (write.domain == domain) {
          result.add(write);
        }
      } catch (_) {
        // Skip corrupted entries.
      }
    }
    return result;
  }

  /// Clear all pending writes for a given [domain].
  Future<void> clearDomain(String domain) async {
    final entries = await _queueStore.readEntries();
    final keysToDelete = <Object?>[];
    for (final entry in entries) {
      final raw = entry.value;
      if (raw is Map && raw['domain'] == domain) {
        keysToDelete.add(entry.storageKey);
      }
    }
    for (final key in keysToDelete) {
      await _queueStore.delete(key);
    }
    await _updateStatus();
  }

  /// Exponential backoff with jitter.
  ///
  /// Delay = min(base * 2^attempts + jitter, maxDelay)
  bool _isInBackoff(PendingWrite write, DateTime now) {
    if (write.attempts == 0 || write.lastAttemptAt == null) {
      return false;
    }

    const baseDelay = Duration(seconds: 2);
    const maxDelay = Duration(minutes: 30);

    final exponentialMs = baseDelay.inMilliseconds * pow(2, write.attempts - 1);
    final jitterMs = _random.nextInt(1000);
    final delayMs = min(exponentialMs + jitterMs, maxDelay.inMilliseconds);
    final cooldownEnd = write.lastAttemptAt!.add(
      Duration(milliseconds: delayMs.toInt()),
    );

    return now.isBefore(cooldownEnd);
  }

  Future<void> _updateStatus() async {
    if (await _queueStore.isEmpty()) {
      status.value = SyncEngineStatus.idle;
    } else {
      status.value = SyncEngineStatus.hasFailures;
    }
  }
}
