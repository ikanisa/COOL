import 'support/recorded_auth_fixture.dart';
// Exercises the current Cloudflare client and repository with controlled HTTP replies.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const fixtureRoot = 'test/fixtures/receipt-worker-cold';
const syntheticActor = '99430000-0000-4000-8000-000000000001';
const healthRpc = 'admin_get_receipt_exception_worker_health_v1';
const detailRpc = 'admin_get_receipt_worker_transport_v1';
final observations = <Map<String, Object?>>[];

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$fixtureRoot/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> evidence(String kind, String tier) => fixture(
  'actual-admin-${kind == 'health' ? 'health' : 'detail'}-'
  '${tier == 'pre' ? 'before-transport-cold' : 'after'}',
);

AdminReceiptWorkerTransportQuery originalQuery() {
  final detail = evidence('detail', 'post');
  return (
    requestId: detail['request_id'] as String,
    expiresAt: DateTime.parse(detail['original_expires_at'] as String),
  );
}

http.Response response(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> syntheticAuth(String id) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': syntheticActor, 'session_id': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'user': {
    'id': syntheticActor,
    'aud': 'authenticated',
    'email': 'operator@example.invalid',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-10-02T00:00:00Z',
  },
};

class Harness {
  Harness(this.name);
  final String name;
  final requests = <http.Request>[];
  late CollectCloudflareClient client;
  late ProviderContainer container;
  String tier = 'post';
  String? failedKind;
  Completer<void>? entered;
  Completer<void>? release;

  Future<void> start() async {
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        http.Response reply(Object? body, [int status = 200]) {
          final raw = response(body, status);
          return http.Response.bytes(
            raw.bodyBytes,
            raw.statusCode,
            headers: raw.headers,
            request: request,
          );
        }

        if (request.url.path == '/v1/auth/verify') {
          return reply(
            syntheticAuth(jsonDecode(request.body)['token'] as String),
          );
        }
        if (request.url.path == '/v1/auth/logout') return reply({});
        requests.add(request);
        final rpc = request.url.path.split('/').last;
        if (rpc == 'admin_current_user') {
          return reply({
            'user_id': syntheticActor,
            'display_name': 'Synthetic cold-storage reviewer',
            'phone_masked': null,
            'roles': ['platform_owner'],
            'permissions': [
              'payments.read',
              'notifications.read',
              'system_health.read',
            ],
          });
        }
        final kind = switch (rpc) {
          healthRpc => 'health',
          detailRpc => 'detail',
          _ => throw StateError('Unallowlisted synthetic RPC: $rpc'),
        };
        final observedTier = tier;
        final gate = release;
        if (entered != null && !entered!.isCompleted) entered!.complete();
        if (gate != null) await gate.future;
        if (failedKind == kind) {
          final error =
              fixture('actual-cold-integrity-errors')[kind == 'health'
                      ? 'admin_health'
                      : 'admin_detail']
                  as Map<String, dynamic>;
          // Status500/details are a declared HTTP representation. SQL code,
          // message and stderr remain exact observed denial evidence.
          return reply({
            'code': error['code'],
            'message': error['message'],
            'details': error['actual_sql_stderr'],
            'hint': 'SYNTHETIC_PRIVATE_ERROR_CANARY',
          }, 500);
        }
        return reply(evidence(kind, observedTier));
      }),
    );
    await installRecordedAuthFixture(
      client,
      email: 'operator@example.invalid',
      token: 'cold-consumer-a',
      type: CollectOtpType.email,
    );
    final clock = DateTime.parse(
      evidence('health', 'post')['checked_at'] as String,
    );
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => clock),
      ],
    );
    // Identity is fetched through the real repository/provider. Neither the
    // identity nor either worker provider/repository is replaced with a fake.
    expect(container.read(adminAuthSessionScopeProvider), isNotNull);
    final owner = await container.read(adminIdentityProvider.future);
    expect(owner?.roles, contains('platform_owner'));
  }

  AdminRepositoryBase get repository => container.read(adminRepositoryProvider);
  List<http.Request> reads(String kind) => requests
      .where(
        (r) => r.url.path.endsWith(kind == 'health' ? healthRpc : detailRpc),
      )
      .toList();

  Future<Map<String, dynamic>> read(String kind) => kind == 'health'
      ? repository.receiptExceptionWorkerHealth()
      : repository.receiptWorkerTransport(
          originalQuery().requestId,
          expectedExpiresAt: originalQuery().expiresAt,
        );

  void assertOriginalRequest(String kind, String bearer, {int count = 1}) {
    final calls = reads(kind);
    expect(calls, hasLength(count));
    for (final request in calls) {
      expect(request.method, 'POST');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'synthetic.invalid');
      expect(
        request.url.path,
        '/v1/rpc/${kind == 'health' ? healthRpc : detailRpc}',
      );
      expect(request.url.queryParameters, isEmpty);
      expect(
        jsonDecode(request.body),
        kind == 'health'
            ? <String, dynamic>{}
            : {'p_request_id': originalQuery().requestId},
      );
      expect(request.headers['authorization'], bearer);
    }
  }

  Future<void> close() async {
    observations.add({
      'test': name,
      'synthetic_http': true,
      'requests': requests
          .map(
            (r) => {
              'method': r.method,
              'path': r.url.path,
              'parameters': jsonDecode(r.body),
              'captured_bearer_sha256': sha256
                  .convert(utf8.encode(r.headers['authorization'] ?? ''))
                  .toString(),
            },
          )
          .toList(),
    });
    if (release != null && !release!.isCompleted) release!.complete();
    container.dispose();
    await client.dispose();
  }
}

Future<void> settle(WidgetTester tester, Harness h, String kind) async {
  // The pinned SDK uses asynchronous JSON decoding. Its fake-zone Future must
  // be advanced by pumps; awaiting it from runAsync would deadlock that zone.
  var ready = false;
  for (var step = 0; step < 100; step++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final session = h.container.read(adminAuthSessionScopeProvider);
    if (session == null || h.client.auth.currentSession == null) {
      ready = true;
      break;
    }
    final AsyncValue<dynamic> state = kind == 'health'
        ? h.container.read(adminReceiptWorkerHealthProvider)
        : h.container.read(
            adminReceiptWorkerTransportProvider((
              query: originalQuery(),
              session: session,
            )),
          );
    if (!state.isLoading ||
        h.release != null &&
            !h.release!.isCompleted &&
            h.entered?.isCompleted == true) {
      ready = true;
      break;
    }
  }
  expect(
    ready,
    isTrue,
    reason: 'Actual provider did not settle within bounded fixture pumps.',
  );
  await tester.pumpAndSettle();
}

Future<void> mount(WidgetTester tester, Harness h, String kind) async {
  await tester.binding.setSurfaceSize(const Size(820, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(
        theme: CollectTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: kind == 'health'
                  ? const AdminReceiptWorkerCard()
                  : AdminReceiptWorkerTransportCard(query: originalQuery()),
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester, h, kind);
}

void freshEvidence(WidgetTester tester, String kind) {
  expect(
    find.text(originalQuery().requestId),
    kind == 'health' ? findsOneWidget : findsNWidgets(2),
  );
  if (kind == 'health') {
    expect(find.text('Latest job has recorded evidence'), findsOneWidget);
    expect(find.text('Investigate original job transport'), findsOneWidget);
    expect(
      find.text('Most recent recorded worker result: completed'),
      findsOneWidget,
    );
  } else {
    expect(find.text('Original worker receipt recorded'), findsOneWidget);
    expect(
      find.text('Recorded original worker result: completed'),
      findsOneWidget,
    );
    expect(
      find.text('HTTP accepted; check original worker receipt'),
      findsOneWidget,
    );
    expect(find.text('Durable scan acknowledgement ID'), findsOneWidget);
    expect(
      find.textContaining(
        'HTTP acceptance does not establish receipt creation or SMS delivery',
      ),
      findsOneWidget,
    );
  }
  expect(tester.takeException(), isNull);
}

void noStaleEvidence(String kind, {bool denied = false}) {
  expect(find.text(originalQuery().requestId), findsNothing);
  expect(find.text('Investigate original job transport'), findsNothing);
  expect(find.text('Latest job has recorded evidence'), findsNothing);
  expect(find.text('Original worker receipt recorded'), findsNothing);
  expect(find.text('Recorded original worker result: completed'), findsNothing);
  expect(
    find.text('Most recent recorded worker result: completed'),
    findsNothing,
  );
  expect(
    find.text('HTTP accepted; check original worker receipt'),
    findsNothing,
  );
  expect(find.text('Durable scan acknowledgement ID'), findsNothing);
  expect(find.text('Original worker receipt pending'), findsNothing);
  expect(
    find.text('No HTTP dispatch observations are recorded for this job.'),
    findsNothing,
  );
  for (final private in [
    'receipt_worker_history_integrity',
    'read_logical',
    '55000',
    'SYNTHETIC_PRIVATE_ERROR_CANARY',
    'PL/pgSQL',
  ]) {
    expect(find.textContaining(private), findsNothing);
  }
  if (denied) {
    expect(find.textContaining('access is required'), findsOneWidget);
  } else {
    expect(
      find.text(
        kind == 'health'
            ? 'Exception worker evidence could not be verified. Refresh and check current access.'
            : 'Job transport evidence could not be verified. Refresh and check current access.',
      ),
      findsOneWidget,
    );
  }
}

void main() {
  tearDownAll(() {
    final path = Platform.environment['COLD_CONSUMER_OBSERVATIONS'];
    if (path != null) {
      File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'synthetic_http': true,
          'scope':
              'Actual canonical repository/provider/cards with pinned synthetic authenticated SDK; no hosted provider-delivery assertion',
          'observations': observations,
        }),
      );
    }
  });

  for (final kind in ['health', 'detail']) {
    for (final tier in ['pre', 'post']) {
      test(
        'SDK $kind $tier exact RPC parameters captured Bearer and actual SQL result',
        () async {
          final h = Harness('sdk-$kind-$tier');
          await h.start();
          addTearDown(h.close);
          h.tier = tier;
          final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
          final raw = await h.read(kind);
          expect(raw, evidence(kind, tier));
          h.assertOriginalRequest(kind, bearer);
        },
      );
    }
    test(
      'SDK $kind exact observed55000 refuses one invocation without absence or retry',
      () async {
        final h = Harness('sdk-$kind-integrity');
        await h.start();
        addTearDown(h.close);
        h.failedKind = kind;
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        await expectLater(
          h.read(kind),
          throwsA(
            isA<CollectApiException>()
                .having((e) => e.code, 'actual SQL code', '55000')
                .having(
                  (e) => e.message,
                  'actual SQL denial',
                  'receipt_worker_history_integrity',
                ),
          ),
        );
        h.assertOriginalRequest(kind, bearer);
      },
    );
    test(
      'SDK pending reconstructed $kind read rejects departed session after response',
      () async {
        final h = Harness('sdk-$kind-departed');
        await h.start();
        addTearDown(h.close);
        h.entered = Completer<void>();
        h.release = Completer<void>();
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        final assertion = expectLater(
          h.read(kind),
          throwsA(isA<AdminSessionChanged>()),
        );
        await h.entered!.future;
        await h.client.auth.signOut();
        h.release!.complete();
        await assertion;
        h.assertOriginalRequest(kind, bearer);
      },
    );

    testWidgets(
      'Actual $kind card shows fresh reconstructed original evidence via repository',
      (tester) async {
        final h = Harness('widget-$kind-healthy');
        await tester.runAsync(h.start);
        addTearDown(h.close);
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        await mount(tester, h, kind);
        freshEvidence(tester, kind);
        h.assertOriginalRequest(kind, bearer);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Actual $kind card initial observed55000 stays unverified without private errors',
      (tester) async {
        final h = Harness('widget-$kind-initial-integrity');
        await tester.runAsync(h.start);
        addTearDown(h.close);
        h.failedKind = kind;
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        await mount(tester, h, kind);
        noStaleEvidence(kind);
        h.assertOriginalRequest(kind, bearer);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Actual $kind healthy to failed refresh clears stale evidence while pending and after55000',
      (tester) async {
        final h = Harness('widget-$kind-refresh-integrity');
        await tester.runAsync(h.start);
        addTearDown(h.close);
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        await mount(tester, h, kind);
        freshEvidence(tester, kind);
        h.failedKind = kind;
        h.entered = Completer<void>();
        h.release = Completer<void>();
        final label = kind == 'health'
            ? 'Refresh exception worker'
            : 'Refresh original job transport';
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settle(tester, h, kind);
        expect(h.entered!.isCompleted, isTrue);
        expect(
          find.text(
            kind == 'health'
                ? 'Loading exception worker evidence…'
                : 'Loading original job transport…',
          ),
          findsOneWidget,
        );
        expect(find.text(originalQuery().requestId), findsNothing);
        expect(find.text('Investigate original job transport'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
        h.release!.complete();
        await settle(tester, h, kind);
        noStaleEvidence(kind);
        h.assertOriginalRequest(kind, bearer, count: 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Actual $kind pending reconstructed response cannot cross session departure',
      (tester) async {
        final h = Harness('widget-$kind-departed');
        await tester.runAsync(h.start);
        addTearDown(h.close);
        h.entered = Completer<void>();
        h.release = Completer<void>();
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        await mount(tester, h, kind);
        expect(h.entered!.isCompleted, isTrue);
        await tester.runAsync(() => h.client.auth.signOut());
        await settle(tester, h, kind);
        h.release!.complete();
        await settle(tester, h, kind);
        noStaleEvidence(kind, denied: true);
        expect(h.container.read(adminAuthSessionScopeProvider), isNull);
        h.assertOriginalRequest(kind, bearer);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
