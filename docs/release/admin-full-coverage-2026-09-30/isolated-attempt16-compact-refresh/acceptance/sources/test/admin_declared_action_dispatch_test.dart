import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_contracts_test.dart' as contracts;
import 'admin_action_session_test.dart' as sdk;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() async {
    requests = [];
    respond = (_) async => sdk.response({});
    client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/verify')) {
          final values = (jsonDecode(r.body)['token'] as String).split('|');
          final receipt = sdk.authReceipt(values[0], values[1]);
          if (values[0] == 'expired-matrix-session') {
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
          return sdk.response(receipt);
        }
        requests.add(r);
        final reply = await respond(r);
        return http.Response.bytes(
          reply.bodyBytes,
          reply.statusCode,
          headers: reply.headers,
          request: r,
        );
      }),
    );
    await sdk.session(client, 'matrix-session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  for (final (rpc, params, ack) in contracts.adminActionContractFixtures()) {
    test(
      '$rpc exact receipt uses captured Bearer and frozen request',
      () async {
        final token = client.auth.currentSession!.accessToken;
        final source = Map<String, dynamic>.of(params);
        final began = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          began.complete();
          await release.future;
          return sdk.response(ack);
        };
        final pending = repository.action(rpc, source);
        await began.future;
        source['client_mutated_after_dispatch'] = true;
        release.complete();
        expect(await pending, ack);
        expect(requests, hasLength(1));
        expect(requests.single.url.path.split('/').last, rpc);
        expect(requests.single.headers['Authorization'], 'Bearer $token');
        expect(jsonDecode(requests.single.body), params);
      },
    );
    test('$rpc incomplete ACK is never accepted', () async {
      await expectLater(repository.action(rpc, params), throwsFormatException);
      expect(requests, hasLength(1));
    });
    test(
      '$rpc genuine permission denial is not translated to success',
      () async {
        respond = (_) async => sdk.response({
          'code': '42501',
          'message': '$rpc permission denied',
        }, 403);
        await expectLater(
          repository.action(rpc, params),
          throwsA(isA<PostgrestException>()),
        );
        expect(requests, hasLength(1));
      },
    );
    test('$rpc expired JWT is denied before HTTP dispatch', () async {
      await sdk.session(client, 'expired-matrix-session');
      expect(adminSessionKey(client.auth.currentSession), isNull);
      repository = AdminRepository(client);
      await expectLater(
        repository.action(rpc, params),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(requests, isEmpty);
    });
    for (final switchBack in [false, true]) {
      test(
        '$rpc suppresses old late ACK after session change; A-B-A=$switchBack',
        () async {
          final began = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            began.complete();
            await release.future;
            return sdk.response(ack);
          };
          final pending = repository.action(rpc, params);
          final rejected = expectLater(
            pending,
            throwsA(isA<AdminSessionChanged>()),
          );
          await began.future;
          await sdk.session(client, 'matrix-session-b');
          if (switchBack) await sdk.session(client, 'matrix-session-a');
          release.complete();
          await rejected;
          expect(requests, hasLength(1));
        },
      );
    }
  }
}
