import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_automations_page.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_shadow_runs.dart';
import 'package:collect_app/admin/shared/components/admin_page.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'contracts/collect-shadow-supervisor-v1.fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

final _now = DateTime.parse(_fixture()['checked_at'] as String);
const _identity = AdminIdentity(
  userId: '00000000-0000-4000-8000-000000000001',
  displayName: 'Synthetic reviewer',
  roles: ['admin'],
  permissions: ['system_health.read', 'notifications.read'],
);

Map<String, dynamic> _run(int number, {int minutesAgo = 0}) {
  final row = _copy(
    (_fixture()['rows'] as List).single as Map<String, dynamic>,
  );
  final start = DateTime.parse(
    row['started_at'] as String,
  ).subtract(Duration(minutes: minutesAgo));
  return row
    ..['run_id'] = '00000000-0000-4000-8000-${'$number'.padLeft(12, '0')}'
    ..['request_id'] = '00000000-0000-4000-8001-${'$number'.padLeft(12, '0')}'
    ..['started_at'] = start.toIso8601String()
    ..['lease_expires_at'] = start
        .add(const Duration(seconds: 120))
        .toIso8601String()
    ..['sampled_at'] = start.add(const Duration(seconds: 2)).toIso8601String()
    ..['completed_at'] = start
        .add(const Duration(seconds: 3))
        .toIso8601String();
}

Map<String, dynamic> _active() {
  final fixture = _fixture();
  final row = (fixture['rows'] as List).single as Map<String, dynamic>;
  row
    ..['status'] = 'running'
    ..['completed_at'] = null
    ..['sampled_at'] = null
    ..['summary'] = null;
  fixture['lease'] = {
    'state': 'active',
    'fence_version': row['fence_version'],
    'active_run_id': row['run_id'],
    'lease_expires_at': row['lease_expires_at'],
  };
  // Lease expires while the 60-second history-read window remains fresh.
  fixture['checked_at'] = DateTime.parse(
    row['lease_expires_at'] as String,
  ).subtract(const Duration(seconds: 10)).toIso8601String();
  return fixture;
}

class _Repository extends AdminEvidenceRepository {
  _Repository({this.failure, this.pending, Map<String, dynamic>? response})
    : response = response ?? _fixture();
  final Object? failure;
  final Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> response;
  final calls = <AdminShadowRunsQuery>[];
  final called = Completer<void>();
  int writes = 0;

  @override
  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) async {
    calls.add(
      AdminShadowRunsQuery(
        limit: limit,
        beforeStartedAt: beforeStartedAt,
        beforeRunId: beforeRunId,
      ),
    );
    if (!called.isCompleted) called.complete();
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    final candidates = (response['rows'] as List).where((raw) {
      final row = raw as Map;
      if (beforeStartedAt == null) return true;
      final time = DateTime.parse(
        row['started_at'] as String,
      ).compareTo(beforeStartedAt);
      return time < 0 ||
          time == 0 && (row['run_id'] as String).compareTo(beforeRunId!) < 0;
    }).toList();
    final page = candidates.take(limit).toList();
    return _copy(response)
      ..['rows'] = page
      ..['next_cursor'] = candidates.length <= limit
          ? null
          : {
              'started_at': (page.last as Map)['started_at'],
              'run_id': (page.last as Map)['run_id'],
            };
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    final source =
        jsonDecode(
              File(
                'test/fixtures/admin_operational_health148.json',
              ).readAsStringSync(),
            )
            as Map;
    return Map<String, dynamic>.from(source['receipt'] as Map)
      ..['checked_at'] = _now.toIso8601String()
      ..['sample_valid_until'] = _now
          .add(const Duration(seconds: 60))
          .toIso8601String();
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() async => {
    'enabled': false,
    'queued': 0,
    'awaiting_confirmation': 0,
    'send_started': 0,
    'uncertain': 0,
    'suppressed': 0,
    'active_workers': 0,
    'observed_at': _now.toIso8601String(),
    'oldest_queued_at': null,
  };

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    writes++;
    throw StateError('History must not write.');
  }
}

class _SessionController extends AdminSessionController {
  _SessionController() : super(null) {
    setSession(1);
  }
  void setSession(int generation) => state = (
    key: (userId: _identity.userId, sessionId: 'synthetic-$generation'),
    generation: generation,
  );
}

class _SessionRepository extends _Repository {
  final first = Completer<Map<String, dynamic>>();
  final firstStarted = Completer<void>();
  final secondStarted = Completer<void>();
  int reads = 0;
  @override
  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) async {
    if (++reads == 1) {
      firstStarted.complete();
      return first.future;
    }
    secondStarted.complete();
    return _fixture();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  test(
    'actual backend history validates immutable evidence and read freshness',
    () {
      final history = AdminShadowRunsSnapshot.parse(_fixture());
      expect(history.rows.single.status, AdminShadowRunStatus.completed);
      expect(
        history.rows.single.summary!.observation,
        AdminShadowObservation.unknown,
      );
      expect(
        history.rows.single.summary!.alertCounts.values.reduce((a, b) => a + b),
        13,
      );
      expect(history.lease.state, AdminShadowLeaseState.idle);
      expect(history.isFresh(_now), isTrue);
      expect(history.isFresh(_now.add(const Duration(seconds: 60))), isFalse);
      expect(
        history.isFresh(_now.subtract(const Duration(seconds: 6))),
        isFalse,
      );
      expect(() => history.rows.clear(), throwsUnsupportedError);
      expect(
        () => history.rows.single.summary!.smsCounts.clear(),
        throwsUnsupportedError,
      );
      final older = _fixture()
        ..['checked_at'] = _now.add(const Duration(days: 1)).toIso8601String();
      expect(
        AdminShadowRunsSnapshot.parse(
          older,
        ).isFresh(_now.add(const Duration(days: 1))),
        isTrue,
      );
    },
  );

  test(
    'strict contract rejects keys, types, enum, time, mutation and severity drift',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (f) => f['actor_phone'] = 'PRIVATE_CANARY',
        (f) => f['mode'] = 'live',
        (f) => f['scope'] = 'group',
        (f) => f['total'] = '1',
        (f) => f['total'] = 9007199254740992,
        (f) => f['checked_at'] = '2026-02-30T18:00:04Z',
        (f) => f['checked_at'] = '2026-09-30T20:00:04+02:00',
        (f) => (f['lease'] as Map)['state'] = 'disabled',
        (f) => (f['lease'] as Map)['fence_version'] = 1000000001,
        (f) => (f['lease'] as Map)['fence_version'] = 0,
        (f) => (f['lease'] as Map)['active_run_id'] = 'invalid',
        (f) => ((f['rows'] as List).single as Map)['summary'] = null,
        (f) => ((f['rows'] as List).single as Map)['completed_at'] = null,
        (f) => ((f['rows'] as List).single as Map)['lease_expires_at'] =
            '2026-09-30T18:02:01Z',
        (f) => ((f['rows'] as List).single as Map)['sampled_at'] =
            '2026-09-30T18:00:04Z',
        (f) =>
            (((f['rows'] as List).single as Map)['summary']
                    as Map)['provider_sends'] =
                1,
        (f) =>
            (((f['rows'] as List).single as Map)['summary']
                    as Map)['business_mutations'] =
                1,
        (f) =>
            (((f['rows'] as List).single as Map)['summary']
                    as Map)['checks_recorded'] =
                13.0,
        (f) =>
            (((f['rows'] as List).single as Map)['summary']
                    as Map)['health_status'] =
                'ok',
        (f) =>
            ((((f['rows'] as List).single as Map)['summary']
                        as Map)['alert_counts']
                    as Map)['ok'] =
                10,
        (f) =>
            ((((f['rows'] as List).single as Map)['summary']
                        as Map)['sms_queue']
                    as Map)['enabled'] =
                0,
        (f) =>
            ((((f['rows'] as List).single as Map)['summary']
                        as Map)['sms_queue']
                    as Map)['uncertain'] =
                1,
      ];
      for (final mutate in mutations) {
        final fixture = _fixture();
        mutate(fixture);
        expect(
          () => AdminShadowRunsSnapshot.parse(fixture),
          throwsFormatException,
        );
      }
      final attention = _fixture();
      final summary =
          (((attention['rows'] as List).single as Map)['summary'] as Map);
      summary['health_status'] = 'attention';
      (summary['sms_queue'] as Map)['uncertain'] = 1;
      expect(
        AdminShadowRunsSnapshot.parse(
          attention,
        ).rows.single.summary!.observation,
        AdminShadowObservation.attention,
      );
    },
  );

  test(
    'active and sampled-expired runs retain their actual observation semantics',
    () {
      final active = _active();
      expect(
        AdminShadowRunsSnapshot.parse(active).lease.state,
        AdminShadowLeaseState.active,
      );
      final conflictingFence = _copy(active);
      (conflictingFence['lease'] as Map)['fence_version'] = 2;
      expect(
        () => AdminShadowRunsSnapshot.parse(conflictingFence),
        throwsFormatException,
      );
      final conflictingExpiry = _copy(active);
      (conflictingExpiry['lease'] as Map)['lease_expires_at'] = DateTime.parse(
        (active['lease'] as Map)['lease_expires_at'] as String,
      ).add(const Duration(seconds: 1)).toIso8601String();
      expect(
        () => AdminShadowRunsSnapshot.parse(conflictingExpiry),
        throwsFormatException,
      );
      final expired = _fixture();
      expired['checked_at'] = _now
          .add(const Duration(minutes: 3))
          .toIso8601String();
      final row = (expired['rows'] as List).single as Map;
      row['status'] = 'expired';
      row['completed_at'] = null;
      expired['lease'] = {
        'state': 'expired',
        'fence_version': 1,
        'active_run_id': row['run_id'],
        'lease_expires_at': row['lease_expires_at'],
      };
      expect(
        AdminShadowRunsSnapshot.parse(expired).rows.single.summary,
        isNotNull,
      );
      (expired['lease'] as Map)['state'] = 'active';
      expect(
        () => AdminShadowRunsSnapshot.parse(expired),
        throwsFormatException,
      );
    },
  );

  test(
    'keyset pages validate ordering, paired boundaries and last-row cursors',
    () {
      final first = _fixture()
        ..['rows'] = [_run(3), _run(2, minutesAgo: 3)]
        ..['total'] = 3;
      first['next_cursor'] = {
        'started_at': ((first['rows'] as List).last as Map)['started_at'],
        'run_id': ((first['rows'] as List).last as Map)['run_id'],
      };
      final history = AdminShadowRunsSnapshot.parse(first, limit: 2);
      final next = _fixture()
        ..['rows'] = [_run(1, minutesAgo: 6)]
        ..['total'] = 3;
      expect(
        AdminShadowRunsSnapshot.parse(
          next,
          limit: 2,
          beforeStartedAt: history.nextCursor!.startedAt,
          beforeRunId: history.nextCursor!.runId,
        ).rows.single.runId,
        endsWith('000001'),
      );
      expect(
        () => AdminShadowRunsSnapshot.parse(first, limit: 1),
        throwsFormatException,
      );
      expect(
        () => AdminShadowRunsSnapshot.parse(first, beforeStartedAt: _now),
        throwsFormatException,
      );
      final duplicate = _copy(first)..['rows'] = [_run(3), _run(3)];
      expect(
        () => AdminShadowRunsSnapshot.parse(duplicate, limit: 2),
        throwsFormatException,
      );
      final unordered = _copy(first)
        ..['rows'] = [_run(2, minutesAgo: 3), _run(3)];
      expect(
        () => AdminShadowRunsSnapshot.parse(unordered, limit: 2),
        throwsFormatException,
      );
      final wrongCursor = _copy(first)
        ..['next_cursor'] = {
          'started_at': _now.toIso8601String(),
          'run_id': _run(3)['run_id'],
        };
      expect(
        () => AdminShadowRunsSnapshot.parse(wrongCursor, limit: 2),
        throwsFormatException,
      );
      expect(
        () => AdminShadowRunsSnapshot.parse(
          first,
          limit: 2,
          beforeStartedAt: history.rows.first.startedAt,
          beforeRunId: history.rows.first.runId,
        ),
        throwsFormatException,
      );
    },
  );

  Future<void> mount(
    WidgetTester tester,
    AdminRepositoryBase repository, {
    AdminIdentity identity = _identity,
    DateTime? now,
    double width = 1440,
    double scale = 1,
    bool dark = false,
    bool page = false,
    int pageSize = 20,
    GlobalKey? capture,
    _SessionController? sessions,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminIdentityProvider.overrideWith((ref) async => identity),
          adminRepositoryProvider.overrideWithValue(repository),
          adminClockProvider.overrideWithValue(() => now ?? _now),
          if (sessions != null)
            adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
        ],
        child: MaterialApp(
          theme: dark ? CollectTheme.dark() : CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: ColoredBox(
                color: (dark ? CollectTheme.dark() : CollectTheme.light())
                    .scaffoldBackgroundColor,
                child: page
                    ? const AdminAutomationsPage()
                    : AdminPage(
                        title: 'Manual shadow monitoring',
                        subtitle: 'Synthetic backend fixture · Africa/Kigali',
                        child: AdminShadowRunsView(
                          now: now ?? _now,
                          pageSize: pageSize,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'persisted completed monitoring has historical unknown result and Kigali times',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository);
      expect(find.text('Monitoring finished'), findsOneWidget);
      expect(find.text('Observation unknown'), findsOneWidget);
      expect(
        find.text('History checked 30 Sep 2026 · 20:00 · Africa/Kigali'),
        findsOneWidget,
      );
      expect(
        find.text('Completed 30 Sep 2026 · 20:00 · Africa/Kigali'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Business changes 0 · Provider sends 0'),
        findsOneWidget,
      );
      expect(find.text('Scope: Collect platform · All groups'), findsOneWidget);
      expect(find.text('Run now'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'expired reads hide lease, rows and counters; elapsed lease never stays active',
    (tester) async {
      await mount(
        tester,
        _Repository(),
        now: _now.add(const Duration(seconds: 60)),
      );
      expect(find.text('History read expired'), findsOneWidget);
      expect(find.text('Monitoring finished'), findsNothing);
      expect(find.text('Checks OK'), findsNothing);
      expect(find.text('Lease idle'), findsNothing);
      final active = _active();
      await mount(
        tester,
        _Repository(response: active),
        now: DateTime.parse(
          active['checked_at'] as String,
        ).add(const Duration(seconds: 10)),
      );
      expect(find.text('Lease elapsed; refresh history'), findsOneWidget);
      expect(find.text('Lease active'), findsNothing);
      expect(find.text('No sample recorded'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'loading, empty, unavailable and denied reads stay explicit and private',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final repository = _Repository(pending: pending);
      await mount(tester, repository);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete(
        _fixture()
          ..['rows'] = []
          ..['total'] = 0,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No monitoring runs in this history window'),
        findsOneWidget,
      );
      await mount(tester, const AdminEvidenceRepository());
      expect(find.text('Run telemetry unavailable'), findsOneWidget);
      for (final code in ['PGRST202', '42883']) {
        await mount(
          tester,
          _Repository(
            failure: PostgrestException(
              message: 'PRIVATE_CANARY missing function',
              code: code,
            ),
          ),
        );
        expect(find.text('Run telemetry unavailable'), findsOneWidget);
        expect(find.text('Run history access denied'), findsNothing);
      }
      await mount(
        tester,
        _Repository(
          failure: const PostgrestException(
            message: 'PRIVATE_CANARY session_owner',
            code: '42501',
          ),
        ),
      );
      expect(find.text('Run history access denied'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('each missing permission avoids all history requests', (
    tester,
  ) async {
    for (final permissions in [
      <String>['system_health.read'],
      <String>['notifications.read'],
      <String>[],
    ]) {
      final repository = _Repository();
      await mount(
        tester,
        repository,
        identity: AdminIdentity(
          userId: _identity.userId,
          displayName: 'Denied',
          roles: ['admin'],
          permissions: permissions,
        ),
      );
      expect(find.text('Run history access denied'), findsOneWidget);
      expect(repository.calls, isEmpty);
    }
    await finish(tester);
  });

  testWidgets(
    'section failure preserves separate SMS and scheduler service outcomes',
    (tester) async {
      final repository = _Repository(
        failure: StateError('PRIVATE_CANARY bearer-token'),
      );
      await mount(tester, repository, page: true);
      expect(find.text('Dispatch disabled'), findsOneWidget);
      expect(find.text('Schedule disabled'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Run history read failed'),
        300,
      );
      expect(find.text('Run history read failed'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'keyset navigation and explicit refresh are reads without writes or repeats',
    (tester) async {
      final response = _fixture()
        ..['rows'] = [_run(3), _run(2, minutesAgo: 3), _run(1, minutesAgo: 6)]
        ..['total'] = 3;
      final repository = _Repository(response: response);
      await mount(tester, repository, pageSize: 1);
      await tester.scrollUntilVisible(find.text('Older runs'), 300);
      await tester.tap(find.text('Older runs'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.beforeRunId, _run(3)['run_id']);
      expect(find.textContaining('Run 00000000'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Older runs'), 300);
      await tester.tap(find.text('Older runs'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.beforeRunId, _run(2)['run_id']);
      expect(find.text('Older runs'), findsNothing);
      await tester.scrollUntilVisible(find.text('Refresh history'), 300);
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.beforeRunId, isNull);
      expect(repository.calls.length, 4);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );

  test(
    'disposed provider suppresses a late history response before validation',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final repository = _Repository(pending: pending);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminIdentityProvider.overrideWith((ref) async => _identity),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final provider = adminShadowRunsProvider(const AdminShadowRunsQuery());
      final listener = container.listen(provider, (_, _) {});
      final future = container.read(provider.future);
      await repository.called.future;
      await container.pump();
      listener.close();
      await container.pump();
      final expectation = expectLater(
        future,
        throwsA(isA<AdminSessionChanged>()),
      );
      pending.complete({'PRIVATE_CANARY': 'untrusted response'});
      await expectation;
      container.dispose();
    },
  );

  test(
    'same-owner session change suppresses pending old evidence before parsing',
    () async {
      final sessions = _SessionController();
      final repository = _SessionRepository();
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
          adminIdentityProvider.overrideWith((ref) async => _identity),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final provider = adminShadowRunsProvider(const AdminShadowRunsQuery());
      final listener = container.listen(provider, (_, _) {});
      await repository.firstStarted.future;
      expect(repository.reads, 1);
      sessions.setSession(2);
      await repository.secondStarted.future;
      expect(repository.reads, 2);
      repository.first.complete({
        'PRIVATE_CANARY': 'untrusted old-session response',
      });
      await container.pump();
      final fresh = await container.read(provider.future);
      expect(fresh.rows.single.status, AdminShadowRunStatus.completed);
      expect(container.read(provider).hasError, isFalse);
      listener.close();
      container.dispose();
    },
  );

  testWidgets('same-owner new session clears pagination', (tester) async {
    final sessions = _SessionController();
    final repository = _Repository(
      response: _fixture()
        ..['rows'] = [_run(3), _run(2, minutesAgo: 3)]
        ..['total'] = 2,
    );
    await mount(tester, repository, sessions: sessions, pageSize: 1);
    await tester.scrollUntilVisible(find.text('Older runs'), 300);
    await tester.tap(find.text('Older runs'));
    await tester.pumpAndSettle();
    sessions.setSession(2);
    await tester.pumpAndSettle();
    expect(repository.calls.last.beforeRunId, isNull);
    expect(find.text('Newer runs'), findsNothing);
    await finish(tester);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'desktop ${dark ? 'dark' : 'light'} history capture uses actual synthetic contract',
      (tester) async {
        final capture = GlobalKey();
        await mount(tester, _Repository(), dark: dark, capture: capture);
        expect(find.text('Monitoring finished'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
          await tester.pumpAndSettle();
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'docs/release/collect-codex-shadow-2026-09-30/shadow-history-${dark ? 'dark' : 'light'}-synthetic.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await finish(tester);
      },
    );
  }

  testWidgets(
    '320px at double text retains evidence and refresh without overflow',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository, width: 320, scale: 2);
      await tester.scrollUntilVisible(find.text('Refresh history'), 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final refresh = find.ancestor(
        of: find.text('Refresh history'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(repository.calls.length, 2);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );
}
