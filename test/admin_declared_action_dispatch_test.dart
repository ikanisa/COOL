import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'admin_action_contracts_test.dart' as contracts;
import 'admin_action_session_test.dart' as sdk;

Future<void> refuseExpiredSession(CollectCloudflareClient client) async {
  await client.auth.clearLocalSession();
  final receipt = sdk.authReceipt('expired-declared-session', '0');
  final token = (receipt['access_token'] as String).split('.');
  final claims =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token[1]))))
          as Map<String, dynamic>;
  claims['exp'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
  receipt['access_token'] =
      '${token[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${token[2]}';
  await expectLater(
    () => client.auth.recoverSession(jsonEncode(receipt)),
    throwsA(
      isA<CollectAuthException>().having(
        (error) => error.code,
        'code',
        'invalid_session',
      ),
    ),
  );
  expect(client.auth.currentSession, isNull);
}

void main() {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() async {
    requests = [];
    respond = (_) async => sdk.response({});
    client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((r) async {
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
    for (final lostReply in ['network', '503']) {
      test('$rpc $lostReply never silently repeats an Admin POST', () async {
        var attempts = 0;
        respond = (_) async {
          attempts++;
          if (attempts == 1) {
            if (lostReply == 'network') {
              throw http.ClientException('Synthetic response lost');
            }
            return sdk.response({
              'code': 'synthetic_unavailable',
              'message': 'Synthetic service unavailable',
            }, 503);
          }
          return sdk.response(ack);
        };
        await expectLater(
          repository.action(rpc, params),
          throwsA(
            lostReply == 'network'
                ? isA<http.ClientException>()
                : isA<CollectApiException>(),
          ),
        );
        expect(requests, hasLength(1));
        expect(attempts, 1);
        // A second explicit caller remains possible. Its handling is governed
        // by the server's existing operation contract and idempotency rules.
        expect(await repository.action(rpc, params), ack);
        expect(requests, hasLength(2));
      });
    }
    test(
      '$rpc genuine permission denial is not translated to success',
      () async {
        respond = (_) async => sdk.response({
          'code': '42501',
          'message': '$rpc permission denied',
        }, 403);
        await expectLater(
          repository.action(rpc, params),
          throwsA(isA<CollectApiException>()),
        );
        expect(requests, hasLength(1));
      },
    );
    test('$rpc expired JWT is denied before HTTP dispatch', () async {
      await refuseExpiredSession(client);
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
