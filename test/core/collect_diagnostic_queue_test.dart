import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/logging/app_logger.dart';
import 'package:collect_app/core/logging/collect_diagnostic_queue.dart';
import 'package:collect_app/core/logging/collect_member_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

String _event({
  String build = '1.2.4+23',
  CollectDiagnosticCode code = CollectDiagnosticCode.frameworkFailure,
}) {
  var value = '';
  CollectDiagnostics(
    surface: CollectDiagnosticSurface.member,
    environmentName: 'production',
    buildVersion: build,
    sink: (event) => value = event,
  ).record(code);
  return value;
}

void main() {
  test('only fixed safe events enter the authenticated queue', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.queue.add(_event());
    expect(h.queue.pendingCount, 0);
    h.activate();
    await _settle();
    for (final text in [
      'SYNTHETIC private SMS token phone',
      jsonEncode({...jsonDecode(_event()) as Map, 'error': 'private'}),
      jsonEncode({...jsonDecode(_event()) as Map, 'surface': 'admin'}),
    ]) {
      h.queue.add(text);
    }
    expect(h.queue.pendingCount, 0);
    h.queue.add(_event());
    await h.queue.flush();
    expect(h.sent, hasLength(1));
    expect(h.queue.pendingCount, 0);
    final report = (h.sent.single['reports'] as List).single as Map;
    expect(report['code'], 'frameworkFailure');
    expect(report['source_revision'], 'a' * 40);
    expect(
      report['fingerprint'],
      collectDiagnosticFingerprint(Map<String, Object?>.from(report)),
    );
    expect(jsonEncode(report), isNot(contains('private')));
    expect(report.keys.toSet(), {
      'collect_diagnostic',
      'code',
      'severity',
      'surface',
      'environment',
      'build_version',
      'attempt',
      'elapsed_ms',
      'source_revision',
      'fingerprint',
      'report_id',
      'occurrences',
    });
  });

  test(
    'coalesces safe occurrences before dispatch and preserves immutable retries',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.activate();
      await _settle();
      h.deliver = (_) async => CollectDiagnosticDelivery.retry;
      h.queue.add(_event());
      h.queue.add(_event());
      await h.queue.flush();
      final original = jsonEncode((h.sent.single['reports'] as List).single);
      expect(
        ((h.sent.single['reports'] as List).single as Map)['occurrences'],
        2,
      );
      h.queue.add(_event());
      await h.queue.flush();
      expect(h.sent, hasLength(1));
      h.now = h.now.add(const Duration(seconds: 5));
      h.deliver = (_) async => CollectDiagnosticDelivery.accepted;
      await h.queue.flush();
      expect(h.sent, hasLength(2));
      expect(jsonEncode((h.sent.last['reports'] as List).first), original);
      expect(h.sent.last['reports'] as List, hasLength(2));
      expect(h.queue.pendingCount, 0);
    },
  );

  test(
    'offline queue is bounded and expired events are removed from persistence',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.activate();
      await _settle();
      for (var i = 0; i < 100; i++) {
        h.queue.add(_event(build: '1.2.$i'));
      }
      await _settle();
      expect(h.queue.pendingCount, 64);
      expect(
        utf8.encode(h.store.value!).length,
        lessThanOrEqualTo(CollectDiagnosticQueue.maximumStoredBytes),
      );
      h.now = h.now.add(const Duration(hours: 24, seconds: 1));
      await h.queue.flush();
      await _settle();
      expect(h.sent, isEmpty);
      expect(h.queue.pendingCount, 0);
      expect((jsonDecode(h.store.value!) as Map)['reports'], isEmpty);
    },
  );

  test(
    'a lost acknowledgement restores the same report identity only for its session',
    () async {
      final store = _Store(), one = _Harness(store: store);
      one.activate();
      await _settle();
      one.deliver = (_) async => throw StateError('private network detail');
      one.queue.add(_event());
      await one.queue.flush();
      await one.dispose();
      final original = jsonEncode((one.sent.single['reports'] as List).single);
      final two = _Harness(store: store);
      addTearDown(two.dispose);
      two.activate();
      await _settle();
      expect(two.queue.pendingCount, 1);
      await two.queue.flush();
      expect(jsonEncode((two.sent.single['reports'] as List).single), original);
      two.queue.add(_event());
      await _settle();
      await two.dispose();
      final other = _Harness(store: store);
      addTearDown(other.dispose);
      other.fence = 'b' * 64;
      other.activate();
      await _settle();
      expect(other.queue.pendingCount, 0);
      expect(other.sent, isEmpty);
      expect(store.value, isNot(contains(original)));
    },
  );

  test(
    'account switch clears old queue and late acknowledgement cannot remove new work',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.activate();
      await _settle();
      final started = Completer<void>(),
          gate = Completer<CollectDiagnosticDelivery>();
      h.deliver = (_) {
        started.complete();
        return gate.future;
      };
      h.queue.add(_event());
      final pending = h.queue.flush();
      await started.future;
      h.fence = 'b' * 64;
      h.activate();
      h.queue.add(_event(code: CollectDiagnosticCode.startupFailed));
      gate.complete(CollectDiagnosticDelivery.accepted);
      await pending;
      expect(h.queue.pendingCount, 1);
      h.deliver = (_) async => CollectDiagnosticDelivery.accepted;
      await h.queue.flush();
      expect(
        ((h.sent.last['reports'] as List).single as Map)['code'],
        'startupFailed',
      );
      expect(h.queue.pendingCount, 0);
      h.fence = null;
      h.activate();
      await _settle();
      expect(h.store.value, isNull);
    },
  );

  test(
    'concurrent flushes share one request and permanent rejection drops only that batch',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.activate();
      await _settle();
      final started = Completer<void>(),
          gate = Completer<CollectDiagnosticDelivery>();
      h.deliver = (_) {
        started.complete();
        return gate.future;
      };
      for (var i = 0; i < 10; i++) {
        h.queue.add(_event(build: '2.0.$i'));
      }
      final pending = h.queue.flush();
      await started.future;
      await h.queue.flush();
      expect(h.sent, hasLength(1));
      gate.complete(CollectDiagnosticDelivery.discard);
      await pending;
      expect(h.queue.pendingCount, 2);
    },
  );

  test(
    'corrupt, oversized or unknown-field persisted data is never uploaded',
    () async {
      for (final raw in [
        'private text',
        'x' * 70000,
        jsonEncode({
          'version': 1,
          'fence': 'a' * 64,
          'reports': [],
          'error': 'private',
        }),
      ]) {
        final h = _Harness(store: _Store()..value = raw);
        h.activate();
        await _settle();
        await h.queue.flush();
        expect(h.sent, isEmpty);
        expect(h.queue.pendingCount, 0);
        await h.dispose();
      }
    },
  );

  test(
    'broken storage and reporter failures never emit recursive reports',
    () async {
      final h = _Harness(store: _Store()..broken = true);
      addTearDown(h.dispose);
      h.activate();
      await _settle();
      h.deliver = (_) async => throw StateError('private provider error');
      h.queue.add(_event());
      await h.queue.flush();
      expect(h.sent, hasLength(1));
      expect(h.queue.pendingCount, 1);
      await h.queue.flush();
      expect(h.sent, hasLength(1));
      await h.dispose();
      h.queue.add(_event());
      await h.queue.flush();
      expect(h.sent, hasLength(1));
    },
  );

  testWidgets(
    'late storage acknowledgement retains one writer and the newest session snapshot',
    (tester) async {
      final store = _ControlledStore(), h = _Harness(store: store);
      try {
        h.activate();
        await tester.pump();
        expect(store.writes, hasLength(1));
        h.queue.add(_event());
        h.fence = 'b' * 64;
        h.activate();
        h.queue.add(_event(code: CollectDiagnosticCode.startupFailed));
        await tester.pump(const Duration(seconds: 3));
        expect(
          store.writes,
          hasLength(1),
          reason:
              'A timeout cannot cancel or release the original plugin write.',
        );
        for (var i = 0; i < 10; i++) {
          h.queue.add(_event(code: CollectDiagnosticCode.startupFailed));
          await tester.pump(const Duration(seconds: 3));
        }
        expect(store.writes, hasLength(1));
        store.writes.first.release.complete();
        await tester.pump();
        expect(store.writes, hasLength(2));
        store.writes.last.release.complete();
        await tester.pump();
        final saved = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(saved['fence'], 'b' * 64);
        final reports = saved['reports'] as List;
        expect(reports, hasLength(1));
        final report = (reports.single as Map)['report'] as Map;
        expect(report['code'], 'startupFailed');
        expect(report['occurrences'], 11);
      } finally {
        store.releaseAll();
        await tester.pump();
        await h.dispose();
      }
    },
  );

  testWidgets(
    'stalled persistence does not block bounded diagnostic delivery',
    (tester) async {
      final store = _ControlledStore(), h = _Harness(store: store);
      try {
        h.activate();
        await tester.pump();
        h.queue.add(_event());
        var finished = false;
        final flush = h.queue.flush().then((_) => finished = true);
        await tester.pump(const Duration(seconds: 4));
        expect(finished, isTrue);
        await flush;
        expect(h.sent, hasLength(1));
        expect(h.queue.pendingCount, 0);
        expect(store.writes, hasLength(1));
        h.queue.add(_event(code: CollectDiagnosticCode.startupFailed));
        var nextFinished = false;
        final nextFlush = h.queue.flush().then((_) => nextFinished = true);
        await tester.pump();
        expect(
          nextFinished,
          isTrue,
          reason:
              'A known stalled drain shares its completed observation instead '
              'of attaching another timeout to the unresolved write.',
        );
        await nextFlush;
        expect(h.sent, hasLength(2));
        expect(h.queue.pendingCount, 0);
        expect(store.writes, hasLength(1));
        store.writes.first.release.complete();
        await tester.pump();
        expect(store.writes, hasLength(2));
        store.writes.last.release.complete();
        await tester.pump();
        expect((jsonDecode(store.value!) as Map)['reports'], isEmpty);
      } finally {
        store.releaseAll();
        await tester.pump();
        await h.dispose();
      }
    },
  );

  testWidgets(
    'bounded disposal retains original write custody and the queued logout clear',
    (tester) async {
      final store = _ControlledStore(), h = _Harness(store: store);
      try {
        h.activate();
        await tester.pump();
        h.queue.add(_event());
        h.fence = null;
        h.activate();
        var disposed = false;
        final disposal = h.dispose().then((_) => disposed = true);
        await tester.pump(const Duration(seconds: 3));
        expect(disposed, isTrue);
        await disposal;
        expect(store.writes, hasLength(1));
        h.queue.add(_event());
        await h.queue.flush();
        expect(h.sent, isEmpty);
        store.writes.first.release.complete();
        await tester.pump();
        expect(store.writes, hasLength(2));
        expect(store.writes.last.value, isNull);
        store.writes.last.release.complete();
        await tester.pump();
        expect(store.value, isNull);
      } finally {
        store.releaseAll();
        await tester.pump();
        await h.dispose();
      }
    },
  );

  test(
    'delivery accepts only the exact acknowledged contract and never follows redirects',
    () {
      expect(
        collectDiagnosticReply(202, {'contract_version': 1, 'accepted': true}),
        CollectDiagnosticDelivery.accepted,
      );
      for (final status in [200, 202, 301, 401, 403, 429, 500, 503]) {
        expect(
          collectDiagnosticReply(status, {
            'accepted': true,
            'raw_error': 'private',
          }),
          CollectDiagnosticDelivery.retry,
        );
      }
      expect(
        collectDiagnosticReply(400, null),
        CollectDiagnosticDelivery.discard,
      );
    },
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _Store implements CollectDiagnosticQueueStore {
  String? value;
  bool broken = false;
  @override
  Future<String?> read() async {
    if (broken) throw StateError('private store error');
    return value;
  }

  @override
  Future<void> write(String? next) async {
    if (broken) throw StateError('private store error');
    value = next;
  }
}

class _PendingWrite {
  _PendingWrite(this.value);
  final String? value;
  final release = Completer<void>();
}

class _ControlledStore extends _Store {
  final writes = <_PendingWrite>[];
  bool holdWrites = true;

  @override
  Future<void> write(String? next) async {
    final pending = _PendingWrite(next);
    writes.add(pending);
    if (holdWrites) await pending.release.future;
    value = next;
  }

  void releaseAll() {
    holdWrites = false;
    for (final pending in writes) {
      if (!pending.release.isCompleted) pending.release.complete();
    }
  }
}

class _Harness {
  _Harness({_Store? store}) : store = store ?? _Store() {
    queue = CollectDiagnosticQueue(
      surface: CollectDiagnosticSurface.member,
      store: this.store,
      sourceRevision: 'a' * 40,
      clock: () => now,
      initialDelay: const Duration(days: 1),
    );
  }
  final _Store store;
  late final CollectDiagnosticQueue queue;
  String? fence = 'a' * 64;
  DateTime now = DateTime.utc(2026, 10, 29);
  final sent = <Map<String, dynamic>>[];
  Future<CollectDiagnosticDelivery> Function(Map<String, Object?>) deliver =
      (_) async => CollectDiagnosticDelivery.accepted;
  void activate() {
    final expected = fence;
    queue.activate(
      fence: expected,
      current: () => expected != null && fence == expected,
      send: (body) {
        sent.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
        return deliver(body);
      },
    );
  }

  Future<void> dispose() => queue.dispose();
}
