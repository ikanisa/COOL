import 'package:cool_app/core/sync/sync_engine.dart';
import 'package:cool_app/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Edge-case tests for SyncEngine.
///
/// These complement the happy-path tests in `sync_engine_test.dart` and
/// target resilience scenarios: backoff, concurrency, corruption, and
/// mixed flush outcomes.
void main() {
  late SyncEngine engine;
  late Box<dynamic> testBox;

  const testBoxName = 'test_sync_engine_edge';

  setUp(() async {
    Hive.init(
      '/tmp/hive_sync_engine_edge_${DateTime.now().microsecondsSinceEpoch}',
    );
    testBox = await Hive.openBox<dynamic>(testBoxName);
    engine = SyncEngine(
      boxName: testBoxName,
      maxAttempts: 3,
      staleDuration: const Duration(hours: 1),
      openBox: (_) async => testBox,
    );
  });

  tearDown(() async {
    await testBox.clear();
    await testBox.close();
  });

  // ─────────────────────────────────────────────────────────────
  // 2.4a — Backoff cooldown skips entries correctly
  // ─────────────────────────────────────────────────────────────
  group('backoff cooldown', () {
    test('skips entries still in backoff window', () async {
      // Insert an entry that was just attempted (attempt=1, lastAttemptAt=now).
      // With base delay=2s and attempt=1, cooldown >= 2s.
      final write = PendingWrite(
        id: 'backoff-1',
        domain: 'contribution',
        payload: {'from': 'A'},
        createdAt: DateTime.now(),
        attempts: 1,
        lastAttemptAt: DateTime.now(), // just attempted
      );
      await testBox.put('backoff-1', write.toMap());

      final result = await engine.flush('contribution', (id, payload) async {
        fail('Should not be called for entry in backoff');
      });

      // Entry is in backoff, so it's skipped — not synced, not failed, not discarded.
      expect(result.skippedBackoff, 1);
      expect(result.synced, 0);
      expect(result.failed, 0);
      expect(result.discarded, 0);
      expect(result.isFullyResolved, isFalse);
      // Entry still in the box.
      expect(testBox.containsKey('backoff-1'), isTrue);
    });

    test('processes entries whose backoff window has expired', () async {
      // Insert an entry with an old lastAttemptAt so backoff has expired.
      final write = PendingWrite(
        id: 'backoff-expired',
        domain: 'contribution',
        payload: {'from': 'B'},
        createdAt: DateTime.now(),
        attempts: 1,
        lastAttemptAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await testBox.put('backoff-expired', write.toMap());

      final synced = <String>[];
      final result = await engine.flush('contribution', (id, payload) async {
        synced.add(id);
      });

      expect(result.synced, 1);
      expect(synced, ['backoff-expired']);
      expect(testBox.containsKey('backoff-expired'), isFalse);
    });

    test('first attempt (attempts=0) is never in backoff', () async {
      final write = PendingWrite(
        id: 'fresh-1',
        domain: 'contribution',
        payload: {'from': 'C'},
        createdAt: DateTime.now(),
        attempts: 0,
      );
      await testBox.put('fresh-1', write.toMap());

      final synced = <String>[];
      final result = await engine.flush('contribution', (id, payload) async {
        synced.add(id);
      });

      expect(result.synced, 1);
      expect(result.skippedBackoff, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2.4b — Concurrent flush calls are safe
  // ─────────────────────────────────────────────────────────────
  group('concurrent flush safety', () {
    test(
      'concurrent flush calls do not crash and eventually sync all items',
      () async {
        await engine.enqueue('contribution', {'a': 1}, id: 'concurrent-1');
        await engine.enqueue('contribution', {'a': 2}, id: 'concurrent-2');

        var callCount = 0;

        Future<void> handler(String id, Map<String, dynamic> payload) async {
          callCount++;
          // Simulate some async work
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        // Fire two flushes concurrently.
        final results = await Future.wait([
          engine.flush('contribution', handler),
          engine.flush('contribution', handler),
        ]);

        final totalSynced = results.fold<int>(0, (s, r) => s + r.synced);
        final totalFailed = results.fold<int>(0, (s, r) => s + r.failed);

        // Both flushes may process the same items (no internal lock), but:
        // - No exceptions should be thrown.
        // - All items should eventually be removed.
        // - Total synced should be >= 2 (each entry synced at least once).
        expect(totalSynced, greaterThanOrEqualTo(2));
        expect(totalFailed, 0);
        expect(callCount, greaterThanOrEqualTo(2));
        expect(testBox.isEmpty, isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 2.4c — Corrupt box entries are discarded gracefully
  // ─────────────────────────────────────────────────────────────
  group('corrupt entry handling', () {
    test('discards non-Map entries from the box', () async {
      // Insert garbage data directly.
      await testBox.put('corrupt-string', 'not-a-map');
      await testBox.put('corrupt-int', 42);
      await testBox.put('corrupt-list', <int>[1, 2, 3]);

      final result = await engine.flush('contribution', (id, payload) async {
        fail('Should not be called for corrupt entries');
      });

      expect(result.discarded, 3);
      expect(testBox.isEmpty, isTrue);
    });

    test('discards Map entries with invalid PendingWrite shape', () async {
      // Map but missing required keys.
      await testBox.put('corrupt-map-1', <String, dynamic>{
        'domain': 'contribution',
        // Missing 'id', 'payload', 'created_at'
      });

      // Map with invalid datetime string.
      await testBox.put('corrupt-map-2', <String, dynamic>{
        'id': 'c2',
        'domain': 'contribution',
        'payload': <String, dynamic>{'a': 1},
        'created_at': 'not-a-date',
      });

      final result = await engine.flush('contribution', (id, payload) async {
        fail('Should not be called for corrupt maps');
      });

      expect(result.discarded, 2);
      expect(testBox.isEmpty, isTrue);
    });

    test('valid entries are still processed alongside corrupt ones', () async {
      // One corrupt, one valid.
      await testBox.put('corrupt', 'garbage');

      final write = PendingWrite(
        id: 'valid-1',
        domain: 'contribution',
        payload: {'from': 'Z'},
        createdAt: DateTime.now(),
      );
      await testBox.put('valid-1', write.toMap());

      final synced = <String>[];
      final result = await engine.flush('contribution', (id, payload) async {
        synced.add(id);
      });

      expect(result.discarded, 1);
      expect(result.synced, 1);
      expect(synced, ['valid-1']);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2.4d — Mixed success/failure/stale/exhausted in single flush
  // ─────────────────────────────────────────────────────────────
  group('mixed flush outcomes', () {
    test(
      'single flush produces correct counts for mixed entry states',
      () async {
        // 1) Stale entry (created 2 hours ago, staleDuration=1h)
        final stale = PendingWrite(
          id: 'stale-mix',
          domain: 'contribution',
          payload: {'type': 'stale'},
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        );
        await testBox.put('stale-mix', stale.toMap());

        // 2) Exhausted entry (attempts >= maxAttempts=3)
        final exhausted = PendingWrite(
          id: 'exhausted-mix',
          domain: 'contribution',
          payload: {'type': 'exhausted'},
          createdAt: DateTime.now(),
          attempts: 3,
        );
        await testBox.put('exhausted-mix', exhausted.toMap());

        // 3) Will-succeed entry
        final success = PendingWrite(
          id: 'success-mix',
          domain: 'contribution',
          payload: {'type': 'success'},
          createdAt: DateTime.now(),
        );
        await testBox.put('success-mix', success.toMap());

        // 4) Will-fail entry
        final willFail = PendingWrite(
          id: 'fail-mix',
          domain: 'contribution',
          payload: {'type': 'fail'},
          createdAt: DateTime.now(),
        );
        await testBox.put('fail-mix', willFail.toMap());

        // 5) In-backoff entry
        final backoff = PendingWrite(
          id: 'backoff-mix',
          domain: 'contribution',
          payload: {'type': 'backoff'},
          createdAt: DateTime.now(),
          attempts: 1,
          lastAttemptAt: DateTime.now(),
        );
        await testBox.put('backoff-mix', backoff.toMap());

        final result = await engine.flush('contribution', (id, payload) async {
          if (payload['type'] == 'fail') {
            throw Exception('simulated failure');
          }
        });

        expect(result.synced, 1, reason: 'success-mix');
        expect(result.failed, 1, reason: 'fail-mix');
        expect(result.discarded, 2, reason: 'stale-mix + exhausted-mix');
        expect(result.skippedBackoff, 1, reason: 'backoff-mix');
        expect(result.total, 5);
        expect(result.isFullyResolved, isFalse);

        // Only fail-mix and backoff-mix should remain.
        expect(testBox.length, 2);
        expect(testBox.containsKey('fail-mix'), isTrue);
        expect(testBox.containsKey('backoff-mix'), isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 2.4e — Flush with empty/absent domain returns zero-result
  // ─────────────────────────────────────────────────────────────
  group('flush with empty domain', () {
    test('returns zero-result when no entries exist for domain', () async {
      // Enqueue items for a different domain.
      await engine.enqueue('momo', {'a': 1}, id: 'momo-1');

      final result = await engine.flush('contribution', (id, payload) async {
        fail('Should not be called');
      });

      expect(result.synced, 0);
      expect(result.failed, 0);
      expect(result.discarded, 0);
      expect(result.skippedBackoff, 0);
      expect(result.total, 0);
      expect(result.isFullyResolved, isTrue);
    });

    test('returns zero-result when box is completely empty', () async {
      final result = await engine.flush('contribution', (id, payload) async {
        fail('Should not be called');
      });

      expect(result.total, 0);
      expect(result.isFullyResolved, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Additional edge-case: status transitions
  // ─────────────────────────────────────────────────────────────
  group('status transitions', () {
    test('status transitions through syncing → idle on full flush', () async {
      await engine.enqueue('contribution', {'a': 1}, id: 'st-1');
      expect(engine.status.value, SyncEngineStatus.hasFailures);

      SyncEngineStatus? statusDuringFlush;

      await engine.flush('contribution', (id, payload) async {
        statusDuringFlush = engine.status.value;
      });

      expect(statusDuringFlush, SyncEngineStatus.syncing);
      expect(engine.status.value, SyncEngineStatus.idle);
    });

    test('status stays hasFailures when items remain after flush', () async {
      await engine.enqueue('contribution', {'a': 1}, id: 'rem-1');

      await engine.flush('contribution', (id, payload) async {
        throw Exception('fail');
      });

      expect(engine.status.value, SyncEngineStatus.hasFailures);
    });
  });
}
