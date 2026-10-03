import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_gateway_contracts_test.dart' as identity;
import 'support/admin_gateway_fixture.dart';

const _request = '99790000-0000-4000-8000-000000000002';
final _checked = DateTime.utc(2026, 10, 1, 0, 0, 20);

class _Probe {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
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
    await auth.session(client, 'gateway-matrix-a');
    repository = AdminRepository(client);
  }

  Map<String, dynamic> receipt(String operation) {
    if (operation == 'admin_list_gateway_devices_v1') {
      return adminGatewayListFixture(_checked);
    }
    if (operation == 'admin_get_gateway_owner_request_v1') {
      return adminGatewayRequestFixture(_checked);
    }
    final action = AdminGatewayOwnerAction.values.singleWhere(
      (v) => v.rpc == operation,
    );
    return identity.gatewayReceipt(state: action.resultState.name);
  }

  AdminGatewayOwnerIntent intent(AdminGatewayOwnerAction action) =>
      action == AdminGatewayOwnerAction.enroll
      ? AdminGatewayOwnerIntent.enroll(
          requestId: identity.gatewayRequest,
          identity: AdminGatewayPublicIdentity.parse(
            identity.gatewayPublicIdentity(),
          ),
        )
      : AdminGatewayOwnerIntent.change(
          action: action,
          requestId: identity.gatewayRequest,
          deviceId: identity.gatewayDevice,
          keySha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          signingCertificateSha256: identity.gatewayCertificate,
        );
  Future<Object?> call(String operation) => switch (operation) {
    'admin_list_gateway_devices_v1' => repository.gatewayDevices(),
    'admin_get_gateway_owner_request_v1' => repository.gatewayOwnerRequest(
      _request,
    ),
    _ => repository.gatewayOwnerAction(
      intent(
        AdminGatewayOwnerAction.values.singleWhere((v) => v.rpc == operation),
      ),
    ),
  };
  Map<String, dynamic> body(String operation) => switch (operation) {
    'admin_list_gateway_devices_v1' => {
      'p_limit': 20,
      'p_before_enrolled_at': null,
      'p_before_device_id': null,
    },
    'admin_get_gateway_owner_request_v1' => {'p_request_id': _request},
    _ => intent(
      AdminGatewayOwnerAction.values.singleWhere((v) => v.rpc == operation),
    ).parameters,
  };
}

void main() {
  late _Probe probe;
  setUp(() async {
    probe = _Probe();
    await probe.start();
  });
  tearDown(() => probe.client.dispose());
  final operations = [
    'admin_list_gateway_devices_v1',
    'admin_get_gateway_owner_request_v1',
    for (final action in AdminGatewayOwnerAction.values) action.rpc,
  ];
  for (final operation in operations) {
    test(
      '$operation actual SDK exact target body and captured Bearer',
      () async {
        probe.respond = (_) async => auth.response(probe.receipt(operation));
        final token = probe.client.auth.currentSession!.accessToken;
        await probe.call(operation);
        expect(probe.requests, hasLength(1));
        expect(probe.requests.single.method, 'POST');
        expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
        expect(jsonDecode(probe.requests.single.body), probe.body(operation));
        expect(probe.requests.single.headers['Authorization'], 'Bearer $token');
      },
    );
    for (final failure in [
      'denied',
      '503',
      'lost response',
      'missing receipt',
      'extra private field',
    ]) {
      test(
        '$operation actual SDK $failure has no fallback or mutation retry',
        () async {
          probe.respond = (_) async {
            if (failure == 'lost response')
              throw TimeoutException('PRIVATE_CANARY');
            if (failure == 'denied' || failure == '503') {
              return auth.response({
                'code': failure == 'denied' ? '42501' : 'unavailable',
                'message': 'PRIVATE_CANARY',
              }, failure == 'denied' ? 403 : 503);
            }
            final data = failure == 'missing receipt'
                ? <String, dynamic>{}
                : {
                    ...probe.receipt(operation),
                    'private_context': 'PRIVATE_CANARY',
                  };
            return auth.response(data);
          };
          await expectLater(
            probe.call(operation),
            throwsA(
              failure == 'lost response'
                  ? isA<TimeoutException>()
                  : failure == 'denied' || failure == '503'
                  ? isA<PostgrestException>()
                  : isA<FormatException>(),
            ),
          );
          expect(probe.requests, hasLength(1));
          expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
        },
      );
    }
    for (final switchBack in [false, true]) {
      test(
        '$operation actual SDK suppresses replaced session switchBack=$switchBack',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          probe.respond = (_) async {
            entered.complete();
            await release.future;
            return auth.response(probe.receipt(operation));
          };
          final future = probe.call(operation);
          final rejected = expectLater(
            future,
            throwsA(isA<AdminSessionChanged>()),
          );
          await entered.future;
          await auth.session(probe.client, 'gateway-matrix-b');
          if (switchBack)
            await auth.session(probe.client, 'gateway-matrix-a', nonce: 2);
          release.complete();
          await rejected;
          expect(probe.requests, hasLength(1));
        },
      );
    }
    test(
      '$operation actual SDK same-session refresh preserves pinned request token',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        probe.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(probe.receipt(operation));
        };
        final token = probe.client.auth.currentSession!.accessToken;
        final future = probe.call(operation);
        await entered.future;
        await auth.session(probe.client, 'gateway-matrix-a', nonce: 1);
        release.complete();
        await future;
        expect(probe.requests, hasLength(1));
        expect(probe.requests.single.headers['Authorization'], 'Bearer $token');
      },
    );
    test('$operation actual SDK signed-out caller makes no request', () async {
      await probe.client.auth.signOut();
      await expectLater(
        probe.call(operation),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(probe.requests, isEmpty);
    });
  }

  for (final requestRead in [false, true]) {
    final operation = requestRead
        ? 'admin_get_gateway_owner_request_v1'
        : 'admin_list_gateway_devices_v1';
    final provider = requestRead
        ? adminGatewayRequestProvider(_request)
        : adminGatewayDevicesProvider(const AdminGatewayQuery());
    for (final missing in ['notifications.read', 'system_health.read']) {
      test(
        '$operation production provider denies missing $missing before SDK dispatch',
        () async {
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(probe.client),
              adminRepositoryProvider.overrideWithValue(probe.repository),
              adminIdentityProvider.overrideWith(
                (ref) async => AdminIdentity(
                  userId: auth.actor,
                  displayName: 'Synthetic owner',
                  roles: ['owner'],
                  permissions: [
                    for (final value in [
                      'notifications.read',
                      'system_health.read',
                    ])
                      if (value != missing) value,
                  ],
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await expectLater(
            container.read(provider.future),
            throwsA(isA<AdminGatewayDenied>()),
          );
          expect(probe.requests, isEmpty);
        },
      );
    }
    test(
      '$operation production provider waits for current identity before SDK dispatch',
      () async {
        final identityReady = Completer<AdminIdentity?>();
        probe.respond = (_) async => auth.response(probe.receipt(operation));
        final container = ProviderContainer(
          overrides: [
            supabaseClientProvider.overrideWithValue(probe.client),
            adminRepositoryProvider.overrideWithValue(probe.repository),
            adminIdentityProvider.overrideWith((ref) => identityReady.future),
          ],
        );
        addTearDown(container.dispose);
        final keep = container.listen(provider, (_, _) {});
        addTearDown(keep.close);
        final pending = container.read(provider.future);
        await Future<void>.delayed(Duration.zero);
        expect(probe.requests, isEmpty);
        identityReady.complete(
          AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic owner',
            roles: ['owner'],
            permissions: ['notifications.read', 'system_health.read'],
          ),
        );
        final data = await pending;
        expect(
          data,
          requestRead
              ? isA<AdminGatewayRequestSnapshot>()
              : isA<AdminGatewaySnapshot>(),
        );
        expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
      },
    );
    for (final code in ['42501', 'PGRST202']) {
      test(
        '$operation production provider redacts $code service failure',
        () async {
          probe.respond = (_) async => auth.response({
            'code': code,
            'message': 'PRIVATE_CANARY',
          }, code == '42501' ? 403 : 404);
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(probe.client),
              adminRepositoryProvider.overrideWithValue(probe.repository),
              adminIdentityProvider.overrideWith(
                (ref) async => AdminIdentity(
                  userId: auth.actor,
                  displayName: 'Synthetic owner',
                  roles: ['owner'],
                  permissions: ['notifications.read', 'system_health.read'],
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await expectLater(
            container.read(provider.future),
            throwsA(
              code == '42501'
                  ? isA<AdminGatewayDenied>()
                  : isA<UnsupportedError>(),
            ),
          );
          expect(probe.requests, hasLength(1));
        },
      );
    }
  }
}
