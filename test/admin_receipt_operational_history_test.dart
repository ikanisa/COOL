import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_automatic_gateway_models.dart';
import 'package:collect_app/admin/core/admin_automatic_gateway_view.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_sdk.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_automatic_gateway_models_test.dart' as automatic;

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'test/fixtures/admin_receipt_operational_history_actual/$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
const owner = AdminIdentity(
  userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  displayName: 'Synthetic history reviewer',
  roles: ['platform_owner'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);

class Sessions extends AdminSessionController {
  Sessions() : super(null) {
    change(1);
  }
  void change(int n) => state = (
    key: (userId: owner.userId, sessionId: 'synthetic-$n'),
    generation: n,
  );
}

class Repository extends AdminEvidenceRepository {
  final calls = <String>[];
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
  Completer<Map<String, dynamic>>? first;
  Map<String, dynamic>? pageOverride;
  Map<String, dynamic>? runOverride;
  Map<String, dynamic>? evidenceOverride;
  Object? error;
  @override
  Future<Map<String, dynamic>> automaticReceiptEvidence(
    String id, {
    int limit = 20,
    AdminAutomaticHistoryCursor? before,
  }) async => automatic.automaticFixture('late-contradictory-observation');
  @override
  AdminReceiptOperationalHistoryApi get receiptOperationalHistory =>
      AdminReceiptOperationalHistoryApi(
        rpc: (name, p) async {
          calls.add(name);
          if (error != null) throw error!;
          if (first != null && calls.length == 1) return first!.future;
          if (name == 'admin_get_receipt_operation_run_v1') {
            return runOverride ?? fixture('run-closed');
          }
          if (name == 'admin_list_receipt_operation_starts_v1') {
            return pageOverride ?? fixture('starts-refused');
          }
          return evidenceOverride ?? fixture('evidence-${p['p_section']}');
        },
      );
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  Repository repo, {
  AdminIdentity actor = owner,
  Sessions? sessions,
  DateTime Function()? clock,
  String? runId,
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      adminIdentityProvider.overrideWith((_) async => actor),
      adminAuthSessionScopeProvider.overrideWith((_) => sessions ?? Sessions()),
      adminClockProvider.overrideWithValue(
        clock ??
            () => historyInstant(
              fixture(
                runId == null ? 'starts-refused' : 'evidence-events',
              )['checked_at'],
            ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: CollectTheme.light(),
        home: Scaffold(
          body: runId == null
              ? const SingleChildScrollView(
                  child: AdminReceiptOperationalHistoryCard(),
                )
              : AdminReceiptOperationalRunPage(runId: runId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  test(
    'pinned real repository reads exact operational RPC with captured session token',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            final token = (jsonDecode(r.body)['token'] as String).split('|');
            return auth.response(auth.authReceipt(token[0], token[1]));
          }
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('admin_get_receipt_operation_run_v1')
                  ? fixture('run-closed')
                  : fixture('evidence-events'),
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      addTearDown(client.dispose);
      await auth.session(client, 'operational-history-a');
      final repo = AdminRepository(client);
      final rid = fixture('run-closed')['run_id'] as String;
      await repo.receiptOperationalHistory.run(rid);
      await repo.receiptOperationalHistory.page(
        AdminReceiptHistoryQuery(
          runId: rid,
          section: AdminReceiptHistorySection.events,
        ),
      );
      expect(requests.map((r) => r.url.path), [
        '/rest/v1/rpc/admin_get_receipt_operation_run_v1',
        '/rest/v1/rpc/admin_list_receipt_operation_evidence_v1',
      ]);
      expect(jsonDecode(requests.first.body), {'p_run_id': rid});
      expect(jsonDecode(requests.last.body), {
        'p_run_id': rid,
        'p_section': 'events',
        'p_limit': 20,
        'p_before_at': null,
        'p_before_id': null,
      });
      expect(
        requests.every(
          (r) =>
              r.headers['authorization'] ==
              'Bearer ${client.auth.currentSession!.accessToken}',
        ),
        isTrue,
      );
    },
  );

  test('actual route registry exposes joined operational run detail', () {
    expect(adminRoutePaths, contains('/admin/automations/runs/:id'));
    expect(
      adminReceiptOperationalRunPath(fixture('run-closed')['run_id'] as String),
      startsWith('/admin/automations/runs/'),
    );
  });
  test('read authority does not require management or audit permission', () {
    expect(adminReceiptOperationalHistoryCanRead(owner), isTrue);
    for (final p in owner.permissions) {
      expect(
        adminReceiptOperationalHistoryCanRead(
          AdminIdentity(
            userId: owner.userId,
            displayName: 'Limited',
            roles: owner.roles,
            permissions: owner.permissions.where((x) => x != p).toList(),
          ),
        ),
        isFalse,
      );
    }
  });
  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'actual ordinary producer closed run renders partial history at width $width',
      (tester) async {
        final raw = fixture('run-closed'), repo = Repository();
        await mount(tester, repo, runId: raw['run_id'] as String, width: width);
        expect(
          find.textContaining('Original close summary: handled'),
          findsOneWidget,
        );
        expect(find.textContaining('Historical budgets'), findsOneWidget);
        expect(find.textContaining('Assigned and unprocessed'), findsWidgets);
        expect(find.textContaining('First durable handling'), findsWidgets);
        expect(
          find.textContaining('No current deferral recorded'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('refused begin request is visible with no invented run link', (
    tester,
  ) async {
    final repo = Repository();
    await mount(tester, repo);
    expect(find.text('This start request created no run.'), findsOneWidget);
    expect(find.text('Open operational run evidence'), findsNothing);
    expect(repo.calls.single, 'admin_list_receipt_operation_starts_v1');
  });
  testWidgets('role denial produces no backend history read', (tester) async {
    final repo = Repository();
    await mount(
      tester,
      repo,
      actor: AdminIdentity(
        userId: owner.userId,
        displayName: 'Limited',
        roles: const ['admin'],
        permissions: owner.permissions,
      ),
    );
    expect(repo.calls, isEmpty);
    expect(find.textContaining('current platform owner'), findsOneWidget);
  });
  testWidgets('expired sample hides identifiers and navigation', (
    tester,
  ) async {
    final repo = Repository();
    var at = historyInstant(fixture('starts-refused')['checked_at']);
    await mount(tester, repo, clock: () => at);
    expect(find.text('This start request created no run.'), findsOneWidget);
    at = at.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('This start request created no run.'), findsNothing);
    expect(find.textContaining('expired'), findsOneWidget);
  });
  testWidgets('pending departed session cannot publish retained history', (
    tester,
  ) async {
    final repo = Repository()..first = Completer();
    final sessions = Sessions();
    await mount(tester, repo, sessions: sessions);
    sessions.change(2);
    await tester.pumpAndSettle();
    expect(repo.calls.length, 2);
    final old = fixture('starts-refused');
    old['rows'][0]['request_id'] = '00000000-0000-4000-8000-000000009999';
    repo.first!.complete(old);
    await tester.pumpAndSettle();
    expect(repo.calls.length, 2);
    expect(
      find.text('Request 00000000-0000-4000-8000-000000009999'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'read-only actual SDK sends closed RPC parameters to pinned repository',
    (tester) async {
      final repo = Repository();
      await mount(
        tester,
        repo,
        runId: fixture('run-closed')['run_id'] as String,
      );
      expect(
        repo.calls,
        containsAll([
          'admin_get_receipt_operation_run_v1',
          'admin_list_receipt_operation_evidence_v1',
        ]),
      );
      expect(
        repo.calls.any(
          (x) =>
              x.contains('execute') ||
              x.contains('configure') ||
              x.contains('stop'),
        ),
        isFalse,
      );
    },
  );
  testWidgets('actual operational detail navigation survives route reload', (
    tester,
  ) async {
    final raw = fixture('run-closed'), repo = Repository();
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        adminIdentityProvider.overrideWith((_) async => owner),
        adminAuthSessionScopeProvider.overrideWith((_) => Sessions()),
        adminClockProvider.overrideWithValue(
          () => historyInstant(fixture('evidence-events')['checked_at']),
        ),
      ],
    );
    addTearDown(c.dispose);
    final path = adminReceiptOperationalRunPath(raw['run_id'] as String);
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: '/admin/automations/runs/:id',
          builder: (context, state) => Scaffold(
            body: AdminReceiptOperationalRunPage(
              runId: state.pathParameters['id']!,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: CollectTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Run ${raw['run_id']}'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, path);
  });
  testWidgets('actual old configuration remains unavailable in run view', (
    tester,
  ) async {
    final repo = Repository()..runOverride = fixture('run-config-unavailable');
    await mount(
      tester,
      repo,
      runId: fixture('run-closed')['run_id'] as String,
      clock: () => historyInstant(repo.runOverride!['checked_at']),
    );
    expect(
      find.text(
        'Historical configuration unavailable. No current budget limit is substituted.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Original close summary'), findsOneWidget);
  });
  testWidgets('unavailable deployed reader produces a bounded failure state', (
    tester,
  ) async {
    final repo = Repository()..error = UnsupportedError('reader unavailable');
    await mount(tester, repo);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(find.text('Open operational run evidence'), findsNothing);
  });
  for (final audit in [false, true]) {
    testWidgets(
      'operational run audit links require independent audit read $audit',
      (tester) async {
        final actor = AdminIdentity(
          userId: owner.userId,
          displayName: owner.displayName,
          roles: owner.roles,
          permissions: [...owner.permissions, if (audit) 'audit.read'],
        );
        await mount(
          tester,
          Repository(),
          runId: fixture('run-closed')['run_id'] as String,
          actor: actor,
        );
        expect(find.byType(AdminEntityAuditLink), findsNWidgets(3));
        expect(
          find.text('View action history'),
          audit ? findsNWidgets(3) : findsNothing,
        );
      },
    );
  }
  for (final source in ['events', 'backlog_results']) {
    testWidgets(
      'actual $source source references use supported route identity',
      (tester) async {
        final repo = Repository();
        final data = fixture('evidence-$source');
        final row = (data['rows'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (r) => source == 'events'
                  ? r['transaction_sms_id'] != null
                  : r['receipt_id'] != null,
            );
        final expected = source == 'events'
            ? '/admin/transactions/momo:${row['transaction_sms_id']}'
            : '/admin/sms-receipts/${row['receipt_id']}';
        final c = ProviderContainer(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repo),
            adminIdentityProvider.overrideWith((_) async => owner),
            adminAuthSessionScopeProvider.overrideWith((_) => Sessions()),
            adminClockProvider.overrideWithValue(
              () => historyInstant(data['checked_at']),
            ),
          ],
        );
        addTearDown(c.dispose);
        final router = GoRouter(
          initialLocation: '/history',
          routes: [
            GoRoute(
              path: '/history',
              builder: (_, _) => Scaffold(
                body: SingleChildScrollView(
                  child: AdminReceiptHistoryPager(
                    runId: data['run_id'] as String,
                    section: AdminReceiptHistorySection.values.firstWhere(
                      (s) => s.wire == source,
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: source == 'events'
                  ? '/admin/transactions/:id'
                  : '/admin/sms-receipts/:id',
              builder: (_, state) => Scaffold(body: Text(state.uri.path)),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(
              theme: CollectTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find
            .widgetWithText(
              TextButton,
              source == 'events'
                  ? 'Open transaction investigation'
                  : 'Open receipt evidence',
            )
            .first;
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
        expect(router.canPop(), isTrue);
      },
    );
  }
  for (final departed in [false, true]) {
    testWidgets(
      'actual automatic attempt joins operational run with current session $departed',
      (tester) async {
        final raw = automatic.automaticFixture(
              'late-contradictory-observation',
            ),
            sessions = Sessions();
        final c = ProviderContainer(
          overrides: [
            adminRepositoryProvider.overrideWithValue(Repository()),
            adminIdentityProvider.overrideWith((_) async => owner),
            adminAuthSessionScopeProvider.overrideWith((_) => sessions),
            adminClockProvider.overrideWithValue(
              () => DateTime.parse(raw['checked_at'] as String),
            ),
          ],
        );
        addTearDown(c.dispose);
        final router = GoRouter(
          initialLocation: '/investigation',
          routes: [
            GoRoute(
              path: '/investigation',
              builder: (_, _) => Scaffold(
                body: SingleChildScrollView(
                  child: AdminAutomaticReceiptCard(
                    receiptId: raw['receipt_id'] as String,
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/admin/automations/runs/:id',
              builder: (_, state) => Scaffold(body: Text(state.uri.path)),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(
              theme: CollectTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.widgetWithText(
          TextButton,
          'Open operational run evidence',
        );
        expect(finder, findsOneWidget);
        final callback = tester.widget<TextButton>(finder).onPressed!;
        if (departed) sessions.change(2);
        callback();
        await tester.pumpAndSettle();
        expect(router.canPop(), !departed);
        if (!departed) {
          expect(
            find.text(
              adminReceiptOperationalRunPath(
                (raw['attempt'] as Map)['run_id'] as String,
              ),
            ),
            findsOneWidget,
          );
        }
      },
    );
  }
  testWidgets(
    'actual registered router supports operational deep link and reload without manage permission',
    (tester) async {
      final raw = fixture('run-closed'), repo = Repository();
      final c = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(repo),
          adminIdentityProvider.overrideWith((_) async => owner),
          adminAuthSessionScopeProvider.overrideWith((_) => Sessions()),
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
          adminClockProvider.overrideWithValue(
            () => historyInstant(fixture('evidence-events')['checked_at']),
          ),
        ],
      );
      addTearDown(c.dispose);
      final router = c.read(adminRouterProvider);
      addTearDown(router.dispose);
      final path = adminReceiptOperationalRunPath(raw['run_id'] as String);
      router.go(path);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: CollectTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminReceiptOperationalRunPage), findsOneWidget);
      expect(find.text('Run ${raw['run_id']}'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, path);
      router.go('/admin/automations');
      await tester.pumpAndSettle();
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(AdminReceiptOperationalRunPage), findsOneWidget);
      expect(find.text('Run ${raw['run_id']}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'captured source link refuses expiry before the next timer rebuild',
    (tester) async {
      final raw = fixture('evidence-events');
      var now = historyInstant(raw['checked_at']);
      final c = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(Repository()),
          adminIdentityProvider.overrideWith((_) async => owner),
          adminAuthSessionScopeProvider.overrideWith((_) => Sessions()),
          adminClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      final router = GoRouter(
        initialLocation: '/history',
        routes: [
          GoRoute(
            path: '/history',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: AdminReceiptHistoryPager(
                  runId: raw['run_id'] as String,
                  section: AdminReceiptHistorySection.events,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/transactions/:id',
            builder: (_, state) => Scaffold(body: Text(state.uri.path)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: CollectTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<TextButton>(
            find
                .widgetWithText(TextButton, 'Open transaction investigation')
                .first,
          )
          .onPressed!;
      now = historyInstant(raw['sample_valid_until']);
      callback();
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
    },
  );
  testWidgets(
    'captured automatic run link refuses sample expiry before timer rebuild',
    (tester) async {
      final raw = automatic.automaticFixture('late-contradictory-observation');
      var now = DateTime.parse(raw['checked_at'] as String);
      final c = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(Repository()),
          adminIdentityProvider.overrideWith((_) async => owner),
          adminAuthSessionScopeProvider.overrideWith((_) => Sessions()),
          adminClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      final router = GoRouter(
        initialLocation: '/investigation',
        routes: [
          GoRoute(
            path: '/investigation',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: AdminAutomaticReceiptCard(
                  receiptId: raw['receipt_id'] as String,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/automations/runs/:id',
            builder: (_, state) => Scaffold(body: Text(state.uri.path)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: CollectTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Open operational run evidence'),
          )
          .onPressed!;
      now = DateTime.parse(raw['sample_valid_until'] as String);
      callback();
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
    },
  );
}
