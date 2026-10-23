import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'admin_action_session_test.dart' as auth;

const _sessionA = '99960000-0000-4000-8000-000000000001';
const _sessionB = '99960000-0000-4000-8000-000000000002';
const _reads = <String, Map<String, dynamic>>{
  'admin_get_roster_import': {'p_import_id': auth.target},
  'admin_recover_roster_import': {
    'p_upload_request_id': auth.target,
    'p_pending_request_id': null,
  },
  'admin_list_interrupted_roster_imports': {},
  'admin_inspect_interrupted_roster_import': {
    'p_import_id': auth.target,
    'p_etag':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  },
  'admin_get_roster_transfer_status': {'p_request_id': auth.target},
  'admin_get_interrupted_roster_commit_status': {'p_import_id': auth.target},
};

// Gateway transport does not decode these responses. The production draft and
// typed decoder tests separately prove their exact target/proof/ACK contract.
void main() {
  late CollectCloudflareClient client;
  late CollectAdminRosterGateway gateway;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response({'synthetic_read': true});
    client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          return auth.response({'error': 'Synthetic refresh outage'}, 503);
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
    await auth.session(client, _sessionA);
    gateway = CollectAdminRosterGateway(client);
  });
  tearDown(() async {
    gateway.dispose();
    await client.dispose();
  });

  Future<Object?> call(String name, Map<String, dynamic> params) =>
      name == 'admin_get_roster_import'
      ? gateway.read(params['p_import_id'] as String)
      : gateway.recoveryRpc(name, params);

  for (final entry in _reads.entries) {
    final name = entry.key, params = entry.value;
    test(
      '$name actual SDK read pins its declared target and current Bearer',
      () async {
        await auth.session(client, _sessionA, nonce: 1);
        final token = client.auth.currentSession!.accessToken;
        expect(await call(name, params), {'synthetic_read': true});
        expect(requests, hasLength(1));
        expect(requests.single.url.path, '/v1/rpc/$name');
        expect(requests.single.method, 'POST');
        expect(jsonDecode(requests.single.body), params);
        expect(requests.single.headers['Authorization'], 'Bearer $token');
      },
    );

    test(
      '$name actual SDK permission denial is safe and never becomes a fallback read',
      () async {
        respond = (_) async => auth.response({
          'code': '42501',
          'message': 'PRIVATE_SERVER_DIAGNOSTIC',
        }, 403);
        await expectLater(
          call(name, params),
          throwsA(
            isA<AdminRosterRequestError>().having(
              (error) => error.code,
              'code',
              'roster_access_unavailable',
            ),
          ),
        );
        expect(requests, hasLength(1));
      },
    );

    for (final failure in ['network', '503']) {
      test(
        '$name actual SDK $failure is one transport attempt per explicit read',
        () async {
          respond = (_) async {
            if (failure == 'network') {
              throw http.ClientException('Synthetic read lost');
            }
            return auth.response({
              'code': 'synthetic_unavailable',
              'message': 'unavailable',
            }, 503);
          };
          await expectLater(
            call(name, params),
            throwsA(isA<AdminRosterRequestError>()),
          );
          expect(requests, hasLength(1));
        },
      );
    }

    for (final switchBack in [false, true]) {
      test(
        '$name actual SDK suppresses old read after session change A-B-A=$switchBack',
        () async {
          final began = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            began.complete();
            await release.future;
            return auth.response({'synthetic_read': true});
          };
          final pending = call(name, params);
          final rejected = expectLater(pending, throwsA(isA<StateError>()));
          await began.future;
          await auth.session(client, _sessionB);
          if (switchBack) await auth.session(client, _sessionA, nonce: 2);
          release.complete();
          await rejected;
          expect(requests, hasLength(1));
          await expectLater(call(name, params), throwsA(isA<StateError>()));
          expect(requests, hasLength(1));
        },
      );
    }

    test('$name actual SDK logout denies before another HTTP read', () async {
      await client.auth.signOut(scope: CollectSignOutScope.local);
      await expectLater(call(name, params), throwsA(isA<StateError>()));
      expect(requests, isEmpty);
    });

    test('$name actual SDK disposal denies before another HTTP read', () async {
      gateway.dispose();
      await expectLater(call(name, params), throwsA(isA<StateError>()));
      expect(requests, isEmpty);
    });

    test(
      '$name actual SDK expired token denies before another HTTP read',
      () async {
        // Admit a live recorded session, then let it actually expire. The
        // production client correctly rejects already-expired installation.
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
        final receipt = auth.authReceipt(_sessionA, '9');
        final parts = (receipt['access_token'] as String).split('.');
        final claims = Map<String, dynamic>.from(
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map,
        );
        claims['exp'] = expiry;
        receipt['access_token'] =
            '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
        receipt['expires_at'] = expiry;
        await client.auth.recoverSession(jsonEncode(receipt));
        final wait = expiry * 1000 - DateTime.now().millisecondsSinceEpoch + 50;
        await Future<void>.delayed(
          Duration(milliseconds: wait.clamp(50, 2050)),
        );
        await expectLater(call(name, params), throwsA(isA<StateError>()));
        expect(requests, isEmpty);
      },
    );
  }
}
