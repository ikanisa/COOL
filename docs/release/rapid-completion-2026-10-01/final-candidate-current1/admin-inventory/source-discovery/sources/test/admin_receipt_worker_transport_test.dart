import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_receipt_worker_transport_models.dart';
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
    'receipt-worker-transport-health-20261001/accepted-sql-attempt5';
Map<String, dynamic> _observed(String name) =>
    jsonDecode(
          File('$_fixtureRoot/observed-detail-$name.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
DateTime _instant(Map<String, dynamic> value, String key) =>
    DateTime.parse(value[key] as String);
AdminReceiptWorkerTransportQuery _query(Map<String, dynamic> value) => (
  requestId: value['request_id'] as String,
  expiresAt: _instant(value, 'original_expires_at'),
);
const _owner = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic transport reviewer',
  roles: ['platform_owner'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);

class _Sdk {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    respond = (_) async => auth.response(_observed('accepted'));
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
    await auth.session(client, 'worker-transport-a');
    repository = AdminRepository(client);
  }

  Future<Map<String, dynamic>> read() {
    final query = _query(_observed('accepted'));
    return repository.receiptWorkerTransport(
      query.requestId,
      expectedExpiresAt: query.expiresAt,
    );
  }
}

class _Repository extends AdminEvidenceRepository {
  Map<String, dynamic> raw = _observed('accepted');
  Completer<void>? gate;
  Object? error;
  final queries = <AdminReceiptWorkerTransportQuery>[];
  int healthReads = 0;
  @override
  Future<Map<String, dynamic>> receiptWorkerTransport(
    String requestId, {
    required DateTime expectedExpiresAt,
  }) async {
    queries.add((requestId: requestId, expiresAt: expectedExpiresAt));
    final retained = _copy(raw), pending = gate;
    if (pending != null) await pending.future;
    if (error != null) throw error!;
    return retained;
  }

  @override
  Future<Map<String, dynamic>> receiptExceptionWorkerHealth() async {
    healthReads++;
    // Declared presentation join: real150000 health shape + selected160000
    // original/deadline. It is not an additional observed SQL health row.
    final health =
        jsonDecode(
              File(
                'docs/release/collect-codex-goal-2026-09-30/'
                'receipt-exception-worker-20261001/accepted-sql-attempt8/'
                'observed-worker-health.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return health..addAll({
      'state': 'pending',
      'checked_at': raw['checked_at'],
      'sample_valid_until': raw['sample_valid_until'],
      'last_request_id': raw['request_id'],
      'last_created_at': _instant(
        raw,
        'original_expires_at',
      ).subtract(const Duration(seconds: 90)).toIso8601String(),
      'last_expires_at': raw['original_expires_at'],
      'last_recorded_at': null,
      'last_outcome': null,
      'alerts': ['WORKER_STALE'],
    });
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
  group('Current pinned SDK transport boundary', () {
    late _Sdk sdk;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
    });
    tearDown(() => sdk.client.dispose());
    test(
      'exact original RPC parameters and captured Bearer dispatch once',
      () async {
        final raw = await sdk.read(), request = sdk.requests.single;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/rest/v1/rpc/admin_get_receipt_worker_transport_v1',
        );
        expect(jsonDecode(request.body), {'p_request_id': raw['request_id']});
        expect(
          request.headers['authorization'],
          'Bearer ${sdk.client.auth.currentSession!.accessToken}',
        );
      },
    );
    for (final failure in [
      '403',
      '503',
      'lost',
      'private',
      'malformed',
      'wrong_original',
      'wrong_deadline',
    ]) {
      test(
        '$failure refuses one SDK result without fallback or retry',
        () async {
          sdk.respond = (_) async {
            if (failure == 'lost') throw TimeoutException('PRIVATE_CANARY');
            if (failure == '403' || failure == '503') {
              return auth.response({
                'code': '42501',
                'message': 'PRIVATE_CANARY',
              }, int.parse(failure));
            }
            final raw = _observed('accepted');
            if (failure == 'private') raw['response_body'] = 'PRIVATE_CANARY';
            if (failure == 'malformed') raw['original_status'] = 'delivered';
            if (failure == 'wrong_original') raw['request_id'] = auth.target;
            if (failure == 'wrong_deadline') {
              raw['original_expires_at'] = _instant(
                raw,
                'original_expires_at',
              ).add(const Duration(microseconds: 1)).toIso8601String();
            }
            return auth.response(raw);
          };
          await expectLater(
            sdk.read(),
            throwsA(
              failure == 'lost'
                  ? isA<TimeoutException>()
                  : failure == '403' || failure == '503'
                  ? isA<PostgrestException>()
                  : isA<FormatException>(),
            ),
          );
          expect(sdk.requests, hasLength(1));
        },
      );
    }
    test('invalid original UUID is denied before SDK dispatch', () async {
      await expectLater(
        sdk.repository.receiptWorkerTransport(
          'PRIVATE_CANARY',
          expectedExpiresAt: _query(_observed('accepted')).expiresAt,
        ),
        throwsFormatException,
      );
      expect(sdk.requests, isEmpty);
    });
    test('signed-out SDK read is denied before HTTP', () async {
      await sdk.client.auth.signOut();
      await expectLater(sdk.read(), throwsA(isA<AdminSessionChanged>()));
      expect(sdk.requests, isEmpty);
    });
    test(
      'same-user replacement suppresses the late original response',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        sdk.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(_observed('accepted'));
        };
        final assertion = expectLater(
          sdk.read(),
          throwsA(isA<AdminSessionChanged>()),
        );
        await entered.future;
        await auth.session(sdk.client, 'worker-transport-b');
        release.complete();
        await assertion;
        expect(sdk.requests, hasLength(1));
      },
    );
    test(
      'actual unresolved SDK response times out at its bounded read without retry',
      () async {
        final release = Completer<http.Response>();
        sdk.respond = (_) => release.future;
        await expectLater(sdk.read(), throwsA(isA<TimeoutException>()));
        expect(sdk.requests, hasLength(1));
        release.complete(auth.response(_observed('accepted')));
      },
    );
  });

  group('Authenticated original transport investigation', () {
    late _Sdk sdk;
    late _Repository repository;
    late ProviderContainer container;
    late AdminReceiptWorkerTransportQuery query;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => _owner,
    );
    late StateProvider<DateTime> clock;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
      repository = _Repository();
      query = _query(repository.raw);
      clock = StateProvider((_) => _instant(repository.raw, 'checked_at'));
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
      bool health = false,
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
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: health
                        ? const AdminReceiptWorkerCard()
                        : AdminReceiptWorkerTransportCard(query: query),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    for (final name in [
      'accepted',
      'original-recorded',
      'expired-unknown',
      'expired-fenced',
    ]) {
      testWidgets(
        '$name renders HTTP facts separately from durable original outcome',
        (tester) async {
          repository.raw = _observed(name);
          query = _query(repository.raw);
          container.read(clock.notifier).state = _instant(
            repository.raw,
            'checked_at',
          );
          await mount(tester);
          expect(
            find.text(
              AdminReceiptWorkerTransport.statusLabels[repository
                  .raw['original_status']]!,
            ),
            findsOneWidget,
          );
          expect(
            find.text('HTTP accepted; check original worker receipt'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              'HTTP acceptance does not establish receipt creation or SMS delivery',
            ),
            findsOneWidget,
          );
          expect(
            find.text('Recorded original worker result: completed'),
            name == 'original-recorded' ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Durable scan acknowledgement ID'),
            name == 'original-recorded' ? findsOneWidget : findsNothing,
          );
          expect(repository.queries, [query]);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final absent in [
      'platform_owner',
      'payments.read',
      'notifications.read',
      'system_health.read',
    ]) {
      testWidgets(
        'missing $absent prevents transport reads and exposes no evidence',
        (tester) async {
          container.read(authority.notifier).state = Future.value(
            AdminIdentity(
              userId: auth.actor,
              displayName: 'Synthetic denied',
              roles: absent == 'platform_owner' ? ['admin'] : _owner.roles,
              permissions: _owner.permissions
                  .where((permission) => permission != absent)
                  .toList(),
            ),
          );
          await mount(tester);
          expect(repository.queries, isEmpty);
          expect(
            find.textContaining(
              'Current platform-owner receipt investigation access is required',
            ),
            findsOneWidget,
          );
          expect(find.text(query.requestId), findsNothing);
          expect(find.text('Transport collector'), findsNothing);
        },
      );
    }
    testWidgets(
      'identity belonging to another user cannot dispatch or show transport evidence',
      (tester) async {
        container.read(authority.notifier).state = Future.value(
          const AdminIdentity(
            userId: auth.target,
            displayName: 'Different synthetic identity',
            roles: ['platform_owner'],
            permissions: [
              'payments.read',
              'notifications.read',
              'system_health.read',
            ],
          ),
        );
        await mount(tester);
        expect(repository.queries, isEmpty);
        expect(find.text(query.requestId), findsNothing);
      },
    );
    testWidgets(
      'loading disables refresh; private failure is redacted and explicit refresh recovers',
      (tester) async {
        repository.gate = Completer<void>();
        await mount(tester);
        expect(find.text('Loading original job transport…'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(
                  OutlinedButton,
                  'Refresh original job transport',
                ),
              )
              .onPressed,
          isNull,
        );
        repository.error = StateError('PRIVATE_CANARY');
        repository.gate!.complete();
        await _settle(tester);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.text(query.requestId), findsNothing);
        repository.gate = null;
        repository.error = null;
        await tester.ensureVisible(find.text('Refresh original job transport'));
        await tester.tap(find.text('Refresh original job transport'));
        await _settle(tester);
        expect(find.text('Original worker receipt pending'), findsOneWidget);
        expect(repository.queries, [query, query]);
      },
    );
    for (final failure in ['private', 'wrong_original', 'wrong_deadline']) {
      testWidgets(
        '$failure repository evidence fails closed with no leaked result',
        (tester) async {
          if (failure == 'private') {
            repository.raw['headers'] = 'PRIVATE_CANARY';
          }
          if (failure == 'wrong_original') {
            repository.raw['request_id'] = auth.target;
          }
          if (failure == 'wrong_deadline') {
            repository.raw['original_expires_at'] = _instant(
              repository.raw,
              'original_expires_at',
            ).add(const Duration(microseconds: 1)).toIso8601String();
          }
          await mount(tester);
          expect(find.textContaining('could not be verified'), findsOneWidget);
          expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
          expect(find.text(query.requestId), findsNothing);
          expect(
            find.text('HTTP accepted; check original worker receipt'),
            findsNothing,
          );
          expect(repository.queries, [query]);
        },
      );
    }
    testWidgets('freshness expiry hides IDs outcomes quotas and observations', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text(query.requestId), findsOneWidget);
      container.read(clock.notifier).state = _instant(
        repository.raw,
        'sample_valid_until',
      );
      await tester.pump();
      expect(find.textContaining('evidence expired'), findsOneWidget);
      expect(find.text(query.requestId), findsNothing);
      expect(find.text('Transport collector'), findsNothing);
      expect(
        find.text('HTTP accepted; check original worker receipt'),
        findsNothing,
      );
      expect(repository.queries, [query]);
    });
    testWidgets(
      'permission departure and restoration cannot resurrect a late earlier read',
      (tester) async {
        repository.gate = Completer<void>();
        final old = repository.gate!;
        await mount(tester);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        repository.raw = _observed('original-recorded');
        repository.gate = null;
        container.read(clock.notifier).state = _instant(
          repository.raw,
          'checked_at',
        );
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        old.complete();
        await _settle(tester);
        expect(find.text('Original worker receipt recorded'), findsOneWidget);
        expect(find.text('Original worker receipt pending'), findsNothing);
        expect(repository.queries, [query, query]);
      },
    );
    testWidgets(
      'narrow 320px twice-text view keeps named refresh and heading semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, width: 320, scale: 2);
          expect(tester.takeException(), isNull);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
            findsWidgets,
          );
          await tester.ensureVisible(
            find.text('Refresh original job transport'),
          );
          await tester.tap(find.text('Refresh original job transport'));
          await _settle(tester);
          expect(repository.queries, [query, query]);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'health launch binds exact original and deadline; modal closes explicitly',
      (tester) async {
        await mount(tester, health: true);
        expect(repository.queries, isEmpty);
        await tester.ensureVisible(
          find.text('Investigate original job transport'),
        );
        await tester.tap(find.text('Investigate original job transport'));
        await _settle(tester);
        expect(find.text('Original job transport evidence'), findsOneWidget);
        expect(repository.queries, [query]);
        expect(find.text('Original worker receipt pending'), findsOneWidget);
        await tester.ensureVisible(find.text('Close job transport evidence'));
        await tester.tap(find.text('Close job transport evidence'));
        await _settle(tester);
        expect(find.text('Original job transport evidence'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'same-user session replacement closes an open health investigation',
      (tester) async {
        await mount(tester, health: true);
        await tester.ensureVisible(
          find.text('Investigate original job transport'),
        );
        await tester.tap(find.text('Investigate original job transport'));
        await _settle(tester);
        expect(find.text('Original job transport evidence'), findsOneWidget);
        await tester.runAsync(
          () => auth.session(sdk.client, 'worker-transport-modal-b'),
        );
        await _settle(tester);
        expect(find.text('Original job transport evidence'), findsNothing);
        expect(repository.queries, [query]);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'expired health evidence cannot launch original investigation',
      (tester) async {
        await mount(tester, health: true);
        container.read(clock.notifier).state = _instant(
          repository.raw,
          'sample_valid_until',
        );
        await tester.pump();
        expect(find.text('Investigate original job transport'), findsNothing);
        expect(repository.queries, isEmpty);
      },
    );
  });
}
