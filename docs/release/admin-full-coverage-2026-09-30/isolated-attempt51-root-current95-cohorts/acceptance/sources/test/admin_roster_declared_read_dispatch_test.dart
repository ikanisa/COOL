import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  late SupabaseClient client;
  late SupabaseAdminRosterGateway gateway;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  var expireNextAuth = false;
  setUp(() async {
    expireNextAuth = false;
    requests = [];
    respond = (_) async => auth.response({'synthetic_read': true});
    client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          final receipt = auth.authReceipt(values[0], values[1]);
          if (expireNextAuth) {
            final parts = (receipt['access_token'] as String).split('.');
            final claims =
                jsonDecode(
                      utf8.decode(
                        base64Url.decode(base64Url.normalize(parts[1])),
                      ),
                    )
                    as Map<String, dynamic>;
            claims['exp'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
            receipt['access_token'] =
                '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
          }
          return auth.response(receipt);
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
    gateway = SupabaseAdminRosterGateway(client);
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
        expect(requests.single.url.path, '/rest/v1/rpc/$name');
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
      await client.auth.signOut(scope: SignOutScope.local);
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
        expireNextAuth = true;
        await auth.session(client, _sessionA, nonce: 9);
        await expectLater(call(name, params), throwsA(isA<StateError>()));
        expect(requests, isEmpty);
      },
    );
  }
}
