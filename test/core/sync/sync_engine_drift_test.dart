import 'package:cool_app/core/database/cool_database.dart';
import 'package:cool_app/core/sync/sync_engine.dart';
import 'package:cool_app/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoolDatabase db;
  late SyncEngine engine;

  setUp(() {
    db = CoolDatabase.memory();
    engine = SyncEngine.drift(
      db: db,
      maxAttempts: 3,
      staleDuration: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('stores pending writes in Drift and flushes them', () async {
    await engine.enqueue('contribution', {'from': 'A'}, id: 'drift-1');
    await engine.enqueue('contribution', {'from': 'B'}, id: 'drift-2');

    expect(await engine.pendingCount('contribution'), 2);
    expect(engine.status.value, SyncEngineStatus.hasFailures);

    final synced = <String>[];
    final result = await engine.flush('contribution', (id, payload) async {
      synced.add(id);
    });

    expect(result.synced, 2);
    expect(result.failed, 0);
    expect(result.isFullyResolved, isTrue);
    expect(synced, ['drift-1', 'drift-2']);
    expect(await engine.pendingCount('contribution'), 0);
    expect(engine.status.value, SyncEngineStatus.idle);
  });

  test('persists failed attempts through Drift', () async {
    await engine.enqueue('contribution', {'from': 'A'}, id: 'fail-1');

    final result = await engine.flush('contribution', (id, payload) async {
      throw Exception('server down');
    });

    expect(result.failed, 1);
    expect(result.synced, 0);
    expect(await engine.pendingCount('contribution'), 1);

    final pending = await engine.pendingWrites('contribution');
    expect(pending.single.id, 'fail-1');
    expect(pending.single.attempts, 1);
    expect(pending.single.lastError, contains('server down'));
  });

  test('clears only the requested domain from Drift', () async {
    await engine.enqueue('contribution', {'a': 1}, id: 'contribution-1');
    await engine.enqueue('momo', {'a': 2}, id: 'momo-1');

    await engine.clearDomain('contribution');

    expect(await engine.pendingCount('contribution'), 0);
    expect(await engine.pendingCount('momo'), 1);
    expect(engine.status.value, SyncEngineStatus.hasFailures);
  });
}
