import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_gateway_contracts_test.dart' as fixture;
import 'admin_gateway_models_test.dart' as source;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(fixture.gatewayReceipt());
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
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'gateway-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  AdminGatewayOwnerIntent enrollment() => AdminGatewayOwnerIntent.enroll(
    requestId: fixture.gatewayRequest,
    identity: AdminGatewayPublicIdentity.parse(fixture.gatewayPublicIdentity()),
  );

  test('device list uses pinned authenticated read and paired UTC cursor', () async {
    final data = source.gatewayListFixture()..['limit'] = 10;
    respond = (_) async => auth.response(data);
    final before = DateTime.utc(2026, 10, 2);
    const id = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
    await repository.gatewayDevices(limit: 10,
      beforeEnrolledAt: before, beforeDeviceId: id);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_list_gateway_devices_v1');
    expect(jsonDecode(requests.single.body), {'p_limit': 10,
      'p_before_enrolled_at': before.toIso8601String(), 'p_before_device_id': id});
    expect(requests.single.headers['Authorization'],
      'Bearer ${client.auth.currentSession!.accessToken}');
  });

  test('invalid limits incomplete cursor and request UUID avoid all HTTP calls', () async {
    for (final limit in [0, 51]) {
      await expectLater(repository.gatewayDevices(limit: limit), throwsRangeError);
    }
    await expectLater(repository.gatewayDevices(beforeEnrolledAt: DateTime.utc(2026)), throwsFormatException);
    await expectLater(repository.gatewayDevices(beforeDeviceId: fixture.gatewayDevice), throwsFormatException);
    await expectLater(repository.gatewayDevices(beforeEnrolledAt: DateTime.utc(10000),
      beforeDeviceId: fixture.gatewayDevice), throwsFormatException);
    await expectLater(repository.gatewayOwnerRequest('not-a-UUID'), throwsFormatException);
    expect(requests, isEmpty);
  });

  test('original owner request lookup is read-only and response binds exact UUID', () async {
    final data = source.gatewayRequestFixture();
    final id = data['request_id'] as String;
    respond = (_) async => auth.response(data);
    await repository.gatewayOwnerRequest(id);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_get_gateway_owner_request_v1');
    expect(jsonDecode(requests.single.body), {'p_request_id': id});
    data['request_id'] = fixture.gatewayRequest;
    await expectLater(repository.gatewayOwnerRequest(id), throwsFormatException);
    expect(requests, hasLength(2));
  });

  test('malformed device capability never becomes dispatch or triggers fallback', () async {
    final data = source.gatewayListFixture();
    source.gatewayRow(data)['dispatch_available'] = true;
    respond = (_) async => auth.response(data);
    await expectLater(repository.gatewayDevices(), throwsFormatException);
    expect(requests, hasLength(1));
  });

  test(
    'real SDK enroll uses one exact actor-fenced owner RPC and typed receipt',
    () async {
      final intent = enrollment();
      final receipt = await repository.gatewayOwnerAction(intent);
      expect(receipt.stateAtAction, AdminGatewayDeviceState.pending);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_enroll_gateway_device_v1',
      );
      expect(jsonDecode(requests.single.body), intent.parameters);
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );

  test(
    'partial or mismatched receipts fail once without automatic mutation retry',
    () async {
      for (final body in [
        {'ok': true},
        {...fixture.gatewayReceipt(), 'request_id': fixture.gatewayDevice},
        {...fixture.gatewayReceipt(), 'state_at_action': 'active'},
      ]) {
        respond = (_) async => auth.response(body);
        await expectLater(
          repository.gatewayOwnerAction(enrollment()),
          throwsFormatException,
        );
      }
      expect(requests, hasLength(3));
    },
  );

  test(
    'permission and HTTP uncertainty return no receipt and perform no retry',
    () async {
      for (final code in [403, 503]) {
        respond = (_) async => auth.response({
          'code': code == 403 ? '42501' : 'unavailable',
          'message': 'PRIVATE_CANARY',
        }, code);
        await expectLater(
          repository.gatewayOwnerAction(enrollment()),
          throwsA(isA<PostgrestException>()),
        );
      }
      expect(requests, hasLength(2));
    },
  );

  for (final switchBack in [false, true]) {
    test(
      'replacement owner session suppresses pending receipt; switchBack=$switchBack',
      () async {
        final started = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          started.complete();
          await release.future;
          return auth.response(fixture.gatewayReceipt());
        };
        final pending = repository.gatewayOwnerAction(enrollment());
        final assertion = expectLater(
          pending,
          throwsA(isA<AdminSessionChanged>()),
        );
        await started.future;
        await auth.session(client, 'gateway-b');
        if (switchBack) await auth.session(client, 'gateway-a', nonce: 2);
        release.complete();
        await assertion;
        expect(requests, hasLength(1));
      },
    );
  }
}
