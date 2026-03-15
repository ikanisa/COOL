/// Pending-write sync engine.
///
/// Queues offline writes in Hive and provides a `flush` mechanism that
/// retries with exponential backoff and discards stale entries.
///
/// This is an **explicit** sync engine — callers trigger `flush()`.
/// No background auto-sync. This keeps behavior testable and predictable.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

/// Central pending-write queue backed by Hive.
///
/// Usage:
/// ```dart
/// final engine = SyncEngine();
/// await engine.enqueue('trip', tripPayload);
/// final result = await engine.flush('trip', myTripSyncHandler);
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
    required OpenHiveBox<dynamic> openBox,
  }) : _boxName = boxName,
       _openBox = openBox;

  static const _defaultBoxName = 'sync_engine_queue';

  final String _boxName;

  /// Maximum number of sync attempts before discarding.
  final int maxAttempts;

  /// Entries older than this are considered stale and discarded.
  final Duration staleDuration;

  final OpenHiveBox<dynamic> _openBox;

  /// Current sync engine status for UI consumption.
  final ValueNotifier<SyncEngineStatus> status = ValueNotifier(
    SyncEngineStatus.idle,
  );

  static final Random _random = Random.secure();

  /// Add a pending write to the queue.
  ///
  /// [domain] groups writes by feature (e.g. 'trip', 'momo_pending').
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

    final box = await _openBox(_boxName);
    await box.put(writeId, write.toMap());

    debugPrint('[SyncEngine] Enqueued $domain/$writeId');
    _updateStatus(box);
    return writeId;
  }

  /// Flush all pending writes for a given [domain].
  ///
  /// [handler] is called for each pending item. If it throws, the item's
  /// attempt count is incremented and it stays in the queue (unless max
  /// attempts reached, in which case it is discarded).
  Future<SyncFlushResult> flush(String domain, SyncHandler handler) async {
    final box = await _openBox(_boxName);
    final keys = box.keys.toList(growable: false);
    final now = DateTime.now();

    var synced = 0;
    var failed = 0;
    var discarded = 0;
    var skippedBackoff = 0;

    status.value = SyncEngineStatus.syncing;

    for (final key in keys) {
      final rawEntry = box.get(key);
      if (rawEntry is! Map) {
        await box.delete(key);
        discarded++;
        continue;
      }

      PendingWrite write;
      try {
        write = PendingWrite.fromMap(Map<String, dynamic>.from(rawEntry));
      } catch (_) {
        await box.delete(key);
        discarded++;
        continue;
      }

      // Only process entries for the requested domain.
      if (write.domain != domain) {
        continue;
      }

      // Discard stale entries.
      if (now.difference(write.createdAt) > staleDuration) {
        debugPrint('[SyncEngine] Discarding stale $domain/${write.id}');
        await box.delete(key);
        discarded++;
        continue;
      }

      // Discard entries that exceeded max attempts.
      if (write.attempts >= maxAttempts) {
        debugPrint(
          '[SyncEngine] Discarding $domain/${write.id} after '
          '${write.attempts} attempts',
        );
        await box.delete(key);
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
        await box.delete(key);
        synced++;
        debugPrint('[SyncEngine] Synced $domain/${write.id}');
      } catch (error) {
        write.attempts++;
        write.lastAttemptAt = now;
        write.lastError = error.toString();
        await box.put(key, write.toMap());
        failed++;
        debugPrint(
          '[SyncEngine] Failed $domain/${write.id} attempt '
          '${write.attempts}: $error',
        );
      }
    }

    _updateStatus(box);

    return SyncFlushResult(
      synced: synced,
      failed: failed,
      discarded: discarded,
      skippedBackoff: skippedBackoff,
    );
  }

  /// Returns the number of pending writes for a given [domain].
  Future<int> pendingCount(String domain) async {
    final box = await _openBox(_boxName);
    var count = 0;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map && raw['domain'] == domain) {
        count++;
      }
    }
    return count;
  }

  /// Returns all pending writes (for debugging / UI).
  Future<List<PendingWrite>> pendingWrites(String domain) async {
    final box = await _openBox(_boxName);
    final result = <PendingWrite>[];
    for (final key in box.keys) {
      final raw = box.get(key);
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
    final box = await _openBox(_boxName);
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map && raw['domain'] == domain) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await box.delete(key);
    }
    _updateStatus(box);
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

  void _updateStatus(Box<dynamic> box) {
    if (box.isEmpty) {
      status.value = SyncEngineStatus.idle;
    } else {
      status.value = SyncEngineStatus.hasFailures;
    }
  }
}
