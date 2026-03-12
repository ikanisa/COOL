import 'package:cool_app/core/sync/sync_engine.dart';
import 'package:cool_app/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// In-memory Hive box for testing.
///
/// We use Hive.init with a temp directory so no real disk I/O occurs.
void main() {
  late SyncEngine engine;
  late Box<dynamic> testBox;

  const testBoxName = 'test_sync_engine';

  setUp(() async {
    Hive.init('/tmp/hive_sync_engine_test_${DateTime.now().microsecondsSinceEpoch}');
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

  group('enqueue', () {
    test('stores a pending write', () async {
      final id = await engine.enqueue('trip', {'from': 'A', 'to': 'B'});
      expect(id, isNotEmpty);
      expect(testBox.containsKey(id), isTrue);
    });

    test('accepts a custom id', () async {
      final id = await engine.enqueue(
        'trip',
        {'from': 'X'},
        id: 'custom-123',
      );
      expect(id, 'custom-123');
      expect(testBox.containsKey('custom-123'), isTrue);
    });

    test('updates status to hasFailures after enqueue', () async {
      await engine.enqueue('trip', {'from': 'A'});
      expect(engine.status.value, SyncEngineStatus.hasFailures);
    });
  });

  group('flush', () {
    test('syncs pending writes and removes them', () async {
      await engine.enqueue('trip', {'from': 'A'}, id: 'write-1');
      await engine.enqueue('trip', {'from': 'B'}, id: 'write-2');

      final synced = <String>[];
      final result = await engine.flush('trip', (id, payload) async {
        synced.add(id);
      });

      expect(result.synced, 2);
      expect(result.failed, 0);
      expect(result.isFullyResolved, isTrue);
      expect(synced, ['write-1', 'write-2']);
      expect(testBox.isEmpty, isTrue);
    });

    test('only flushes the requested domain', () async {
      await engine.enqueue('trip', {'from': 'A'}, id: 'trip-1');
      await engine.enqueue('momo', {'amount': 100}, id: 'momo-1');

      final result = await engine.flush('trip', (id, payload) async {});

      expect(result.synced, 1);
      expect(testBox.containsKey('momo-1'), isTrue);
    });

    test('increments attempts on failure', () async {
      await engine.enqueue('trip', {'from': 'A'}, id: 'fail-1');

      final result = await engine.flush('trip', (id, payload) async {
        throw Exception('server down');
      });

      expect(result.failed, 1);
      expect(result.synced, 0);

      final raw = testBox.get('fail-1') as Map;
      expect(raw['attempts'], 1);
      expect(raw['last_error'], contains('server down'));
    });

    test('discards entries exceeding maxAttempts', () async {
      // Manually insert an entry with maxAttempts already reached.
      final write = PendingWrite(
        id: 'exhausted-1',
        domain: 'trip',
        payload: {'from': 'Z'},
        createdAt: DateTime.now(),
        attempts: 3, // maxAttempts = 3
      );
      await testBox.put('exhausted-1', write.toMap());

      final result = await engine.flush('trip', (id, payload) async {
        fail('Should not be called for exhausted entry');
      });

      expect(result.discarded, 1);
      expect(testBox.containsKey('exhausted-1'), isFalse);
    });

    test('discards stale entries', () async {
      final write = PendingWrite(
        id: 'stale-1',
        domain: 'trip',
        payload: {'from': 'old'},
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await testBox.put('stale-1', write.toMap());

      final result = await engine.flush('trip', (id, payload) async {
        fail('Should not be called for stale entry');
      });

      expect(result.discarded, 1);
      expect(testBox.containsKey('stale-1'), isFalse);
    });

    test('updates status to idle when all items flushed', () async {
      await engine.enqueue('trip', {'from': 'A'}, id: 'write-1');
      await engine.flush('trip', (id, payload) async {});
      expect(engine.status.value, SyncEngineStatus.idle);
    });
  });

  group('pendingCount', () {
    test('returns count for domain', () async {
      await engine.enqueue('trip', {'a': 1}, id: 't1');
      await engine.enqueue('trip', {'a': 2}, id: 't2');
      await engine.enqueue('momo', {'a': 3}, id: 'm1');

      expect(await engine.pendingCount('trip'), 2);
      expect(await engine.pendingCount('momo'), 1);
      expect(await engine.pendingCount('other'), 0);
    });
  });

  group('clearDomain', () {
    test('removes all writes for domain', () async {
      await engine.enqueue('trip', {'a': 1}, id: 't1');
      await engine.enqueue('momo', {'a': 2}, id: 'm1');

      await engine.clearDomain('trip');
      expect(await engine.pendingCount('trip'), 0);
      expect(await engine.pendingCount('momo'), 1);
    });
  });

  group('PendingWrite serialization', () {
    test('round-trips through toMap/fromMap', () {
      final original = PendingWrite(
        id: 'test-123',
        domain: 'trip',
        payload: {'from': 'A', 'to': 'B'},
        createdAt: DateTime(2026, 3, 11),
        attempts: 2,
        lastAttemptAt: DateTime(2026, 3, 11, 10),
        lastError: 'timeout',
      );

      final restored = PendingWrite.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.domain, original.domain);
      expect(restored.payload, original.payload);
      expect(restored.attempts, original.attempts);
      expect(restored.lastError, original.lastError);
    });
  });
}
