import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_receipt_worker_health.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

const _fixtureRoot =
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-exception-worker-20261001/accepted-sql-attempt8';
Map<String, dynamic> _observed(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File('$_fixtureRoot/observed-worker-$name.json').readAsStringSync(),
      )
      as Map,
);
Map<String, dynamic> _view(String state) {
  if (state == 'observed') return _observed('health');
  if (state == 'unknown') return _observed('unknown-health');
  if (state == 'expired_without_receipt') return _observed('quota-health');
  if (state == 'unobserved') return _observed('unobserved-health');
  // Presentation variants derive from actual SQL; these two variants are not
  // represented as additional database observations.
  return _observed('health')
    ..['state'] = state
    ..['enabled'] = state != 'inactive';
}

const _owner = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic worker reviewer',
  roles: ['platform_owner'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);

class _Sdk {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    respond = (_) async => auth.response(_observed('health'));
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(parts[0], parts[1]));
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        requests.add(request);
        final result = await respond(request);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'worker-health-a');
    repository = AdminRepository(client);
  }
}

class _Repository extends AdminEvidenceRepository {
  Map<String, dynamic> raw = _observed('health');
  Completer<void>? gate;
  Object? error;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> receiptExceptionWorkerHealth() async {
    reads++;
    final retained = Map<String, dynamic>.from(raw);
    final pending = gate;
    if (pending != null) await pending.future;
    if (error != null) throw error!;
    return retained;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Actual trusted-worker SQL contract', () {
    for (final name in [
      'health',
      'unknown-health',
      'quota-health',
      'unobserved-health',
    ]) {
      test(
        '$name preserves actual state, budget and original-result semantics',
        () {
          final raw = _observed(name);
          final sample = AdminReceiptWorkerHealth.parse(raw);
          expect(sample.state, raw['state']);
          expect(sample.outcome, raw['last_outcome']);
          expect(sample.alerts, raw['alerts']);
          expect(sample.budgets['jobs']!.reserved, raw['day_jobs_reserved']);
          expect(sample.isFresh(sample.checkedAt), isTrue);
          expect(sample.isFresh(sample.validUntil), isFalse);
          expect(
            sample.isFresh(
              sample.checkedAt.subtract(const Duration(seconds: 6)),
            ),
            isFalse,
          );
        },
      );
    }
    test(
      'lowered caps retain actual over-budget reservations without clamping',
      () {
        final sample = AdminReceiptWorkerHealth.parse(
          _observed('quota-health'),
        );
        expect(sample.budgets['jobs'], (reserved: 4, cap: 1));
        expect(() => sample.budgets.clear(), throwsUnsupportedError);
        expect(() => sample.alerts.clear(), throwsUnsupportedError);
      },
    );
    test('all exact fields are required and private fields are refused', () {
      final raw = _observed('health');
      for (final key in raw.keys) {
        expect(
          () => AdminReceiptWorkerHealth.parse({...raw}..remove(key)),
          throwsFormatException,
        );
      }
      for (final key in [
        'phone',
        'error_message',
        'response_body',
        'credential',
        'url',
      ]) {
        expect(
          () => AdminReceiptWorkerHealth.parse({...raw, key: 'PRIVATE_CANARY'}),
          throwsFormatException,
        );
      }
    });
    test('versions, integer budgets, flags and finite states fail closed', () {
      final raw = _observed('health');
      for (final patch in [
        {'contract_version': 2},
        {'contract_version': 1.0},
        {'configuration_revision': 0},
        {'configuration_revision': 1000000001},
        {'day_jobs_cap': 1441},
        {'day_scan_sources_cap': 36001},
        {'day_escalations_cap': 28801},
        {'day_jobs_reserved': -1},
        {'pending_sources': '0'},
        {'enabled': 'true'},
        {'transport_configured': null},
        {'state': 'sent'},
        {'source_scan_complete': true},
        {'financial_action': true},
        {'send_action': true},
        {'external_send': true},
        {'last_outcome': 'sent'},
        {'last_request_id': 'PRIVATE_CANARY'},
      ]) {
        expect(
          () => AdminReceiptWorkerHealth.parse({...raw, ...patch}),
          throwsFormatException,
        );
      }
    });
    test(
      'contradictory state, receipt association and alert facts are refused',
      () {
        final raw = _observed('health');
        for (final patch in [
          {'enabled': false},
          {'state': 'unobserved'},
          {'last_request_id': null},
          {'last_created_at': null},
          {'last_recorded_at': null},
          {'last_outcome': null},
          {
            'alerts': ['ORIGINAL_OUTCOME_UNKNOWN'],
          },
          {
            'alerts': ['ORIGINAL_EXPIRED_UNHANDLED'],
          },
          {
            'alerts': ['TRANSPORT_UNCONFIGURED'],
          },
          {
            'alerts': ['WORKER_STALE'],
          },
          {
            'alerts': ['SOURCE_REFUSALS', 'SOURCE_REFUSALS'],
          },
          {
            'alerts': ['PRIVATE_CANARY'],
          },
          {'alerts': 'WORKER_STALE'},
        ]) {
          expect(
            () => AdminReceiptWorkerHealth.parse({...raw, ...patch}),
            throwsFormatException,
          );
        }
        expect(
          () => AdminReceiptWorkerHealth.parse({
            ..._observed('unknown-health'),
            'alerts': ['WORKER_QUOTA_EXHAUSTED'],
          }),
          throwsFormatException,
        );
        expect(
          () => AdminReceiptWorkerHealth.parse({
            ..._observed('quota-health'),
            'state': 'unknown',
          }),
          throwsFormatException,
        );
      },
    );
    test(
      'canonical UTC, 60-second freshness and 90-second job deadlines are enforced',
      () {
        final raw = _observed('health');
        for (final patch in [
          {'checked_at': '2026-02-30T12:32:36.724681Z'},
          {'checked_at': '2026-10-01T12:32:36.724681+00:00'},
          {'sample_valid_until': raw['checked_at']},
          {'last_expires_at': raw['last_created_at']},
          {'last_created_at': raw['sample_valid_until']},
          {'last_recorded_at': raw['sample_valid_until']},
        ]) {
          expect(
            () => AdminReceiptWorkerHealth.parse({...raw, ...patch}),
            throwsFormatException,
          );
        }
        expect(
          () => AdminReceiptWorkerHealth.parse({
            ..._observed('unknown-health'),
            'state': 'pending',
            'alerts': ['WORKER_QUOTA_EXHAUSTED'],
          }),
          throwsFormatException,
        );
      },
    );
  });

  group('Actual pinned SDK boundary', () {
    late _Sdk sdk;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
    });
    tearDown(() => sdk.client.dispose());
    test(
      'read uses exact RPC, empty parameters and captured authorization',
      () async {
        await sdk.repository.receiptExceptionWorkerHealth();
        final request = sdk.requests.single;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/rest/v1/rpc/admin_get_receipt_exception_worker_health_v1',
        );
        expect(jsonDecode(request.body), {});
        expect(
          request.headers['authorization'],
          'Bearer ${sdk.client.auth.currentSession!.accessToken}',
        );
      },
    );
    for (final failure in ['403', '503', 'lost', 'private', 'malformed']) {
      test('$failure is one attempt with no fallback', () async {
        sdk.respond = (_) async {
          if (failure == 'lost') throw TimeoutException('PRIVATE_CANARY');
          if (failure == '403' || failure == '503') {
            return auth.response({
              'code': '42501',
              'message': 'PRIVATE_CANARY',
            }, int.parse(failure));
          }
          final raw = _observed('health');
          if (failure == 'private') raw['phone'] = 'PRIVATE_CANARY';
          if (failure == 'malformed') raw['state'] = 'delivered';
          return auth.response(raw);
        };
        await expectLater(
          sdk.repository.receiptExceptionWorkerHealth(),
          throwsA(
            failure == 'lost'
                ? isA<TimeoutException>()
                : failure == '403' || failure == '503'
                ? isA<PostgrestException>()
                : isA<FormatException>(),
          ),
        );
        expect(sdk.requests, hasLength(1));
      });
    }
    test(
      'late read after same-user session replacement is suppressed',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        sdk.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(_observed('health'));
        };
        final pending = sdk.repository.receiptExceptionWorkerHealth();
        final checked = expectLater(
          pending,
          throwsA(isA<AdminSessionChanged>()),
        );
        await entered.future;
        await auth.session(sdk.client, 'worker-health-b');
        release.complete();
        await checked;
        expect(sdk.requests, hasLength(1));
      },
    );
    test('unresolved actual SDK read times out without replay', () async {
      final release = Completer<http.Response>();
      sdk.respond = (_) => release.future;
      await expectLater(
        sdk.repository.receiptExceptionWorkerHealth(),
        throwsA(isA<TimeoutException>()),
      );
      expect(sdk.requests, hasLength(1));
      release.complete(auth.response(_observed('health')));
    });
  });

  group('Current session-bound worker view', () {
    late _Sdk sdk;
    late _Repository repository;
    late ProviderContainer container;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => _owner,
    );
    late StateProvider<DateTime> clock;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
      repository = _Repository();
      clock = StateProvider(
        (_) => DateTime.parse(repository.raw['checked_at'] as String),
      );
      container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(sdk.client),
          adminRepositoryProvider.overrideWithValue(repository),
          adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
          adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
          adminClockProvider.overrideWith((ref) {
            final now = ref.watch(clock);
            return () => now;
          }),
        ],
      );
      await container.read(adminIdentityProvider.future);
    });
    tearDown(() async {
      container.dispose();
      await sdk.client.dispose();
    });
    Future<void> mount(
      WidgetTester tester, {
      double width = 640,
      double scale = 1,
    }) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: CollectTheme.light(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: AdminReceiptWorkerCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    for (final state in AdminReceiptWorkerHealth.states.keys) {
      testWidgets('$state has truthful independent health wording', (
        tester,
      ) async {
        repository.raw = _view(state);
        container.read(clock.notifier).state = DateTime.parse(
          repository.raw['checked_at'] as String,
        );
        await mount(tester);
        expect(
          find.text(AdminReceiptWorkerHealth.states[state]!),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Receipt creation, financial handling and SMS delivery have separate evidence',
          ),
          findsOneWidget,
        );
        if (state == 'unknown') {
          expect(
            find.textContaining('can belong to an earlier job'),
            findsOneWidget,
          );
          expect(
            find.text('Most recent recorded worker result: completed'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Expired original job has no'),
            findsNothing,
          );
        }
        if (state == 'expired_without_receipt') {
          expect(
            find.text('Scheduled jobs: 4 reserved / 1 cap'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Original job outcome needs reconciliation'),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
    for (final absent in [
      'platform_owner',
      'payments.read',
      'notifications.read',
      'system_health.read',
    ]) {
      testWidgets('missing $absent prevents reads and hides evidence', (
        tester,
      ) async {
        container.read(authority.notifier).state = Future.value(
          AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic denied',
            roles: absent == 'platform_owner' ? ['admin'] : _owner.roles,
            permissions: _owner.permissions.where((p) => p != absent).toList(),
          ),
        );
        await mount(tester);
        expect(repository.reads, 0);
        expect(find.textContaining('A current platform owner'), findsOneWidget);
        expect(find.text('UTC-day reservations'), findsNothing);
      });
    }
    testWidgets(
      'loading and private failures have safe states and named recovery',
      (tester) async {
        repository.gate = Completer<void>();
        await mount(tester);
        expect(find.text('Loading exception worker evidence…'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Refresh exception worker'),
              )
              .onPressed,
          isNull,
        );
        repository.error = StateError('PRIVATE_CANARY');
        repository.gate!.complete();
        await _settle(tester);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        repository.error = null;
        repository.gate = null;
        await tester.tap(find.text('Refresh exception worker'));
        await _settle(tester);
        expect(
          find.text(AdminReceiptWorkerHealth.states['observed']!),
          findsOneWidget,
        );
        expect(repository.reads, 2);
      },
    );
    testWidgets(
      'expiry hides all historical worker claims, IDs, budgets and links',
      (tester) async {
        await mount(tester);
        final id = repository.raw['last_request_id'] as String;
        expect(find.text(id), findsOneWidget);
        container.read(clock.notifier).state = DateTime.parse(
          repository.raw['sample_valid_until'] as String,
        );
        await tester.pump();
        expect(find.textContaining('evidence expired'), findsOneWidget);
        expect(find.text(id), findsNothing);
        expect(find.text('UTC-day reservations'), findsNothing);
        expect(find.text('Open receipt exceptions'), findsNothing);
      },
    );
    testWidgets(
      'narrow large-text view retains named controls and heading semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, width: 320, scale: 2);
          expect(tester.takeException(), isNull);
          expect(find.text('UTC-day reservations'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
            findsWidgets,
          );
          await tester.ensureVisible(find.text('Refresh exception worker'));
          await tester.tap(find.text('Refresh exception worker'));
          await _settle(tester);
          expect(repository.reads, 2);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'permission departure and restoration never resurrects a pending read',
      (tester) async {
        repository.gate = Completer<void>();
        final release = repository.gate!;
        await mount(tester);
        expect(repository.reads, 1);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        repository.raw = _observed('unknown-health');
        repository.gate = null;
        container.read(clock.notifier).state = DateTime.parse(
          repository.raw['checked_at'] as String,
        );
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        release.complete();
        await _settle(tester);
        expect(repository.reads, 2);
        expect(
          find.text(AdminReceiptWorkerHealth.states['unknown']!),
          findsOneWidget,
        );
        expect(
          find.text(AdminReceiptWorkerHealth.states['observed']!),
          findsNothing,
        );
      },
    );
    testWidgets('link uses the canonical authenticated exception route', (
      tester,
    ) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await container.read(adminRuntimeConfigProvider.future);
      });
      await tester.binding.setSurfaceSize(const Size(1440, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = container.read(adminRouterProvider);
      router.go('/admin/automations');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: CollectTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Receipt exception worker'), findsOneWidget);
      await tester.ensureVisible(find.text('Open receipt exceptions'));
      await tester.tap(find.text('Open receipt exceptions'));
      await _settle(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/exceptions',
      );
      expect(find.text('Exceptions'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
