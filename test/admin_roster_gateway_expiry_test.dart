import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'support/admin_read_fixture.dart';

const _sidA = '99740000-0000-4000-8000-000000000011';
const _sidB = '99740000-0000-4000-8000-000000000012';
Map<String, dynamic> _auth({
  String actor = adminReadActor,
  String sid = _sidA,
  Object? exp,
  String nonce = '0',
}) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': exp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.$nonce',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'user': {
    'id': actor,
    'aud': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': adminReadDate,
  },
};

CollectCloudflareClient _client() => CollectCloudflareClient(
  'https://synthetic.invalid',
  httpClient: MockClient((_) async => _json({'error': 'unavailable'}, 503)),
);

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  for (final exp in <Object?>['future', true, -1, 9007199254740991]) {
    test('gateway rejects malformed or unbounded expiry $exp', () async {
      final client = _client();
      addTearDown(client.dispose);
      expect(
        () => client.auth.recoverSession(jsonEncode(_auth(exp: exp))),
        throwsA(isA<CollectAuthException>()),
      );
      expect(client.auth.currentSession, isNull);
      expect(() => CollectAdminRosterGateway(client), throwsStateError);
    });
  }
  test(
    'gateway rejects response expiry even when JWT expiry is later',
    () async {
      final client = _client();
      addTearDown(client.dispose);
      final receipt = _auth();
      receipt['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
      await client.auth.recoverSession(jsonEncode(receipt));
      expect(() => CollectAdminRosterGateway(client), throwsStateError);
    },
  );
  test(
    'real expiry timer invalidates draft lease without an Auth event and never revives',
    () async {
      final client = _client();
      addTearDown(client.dispose);
      final receipt = _auth();
      receipt['expires_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
      await client.auth.recoverSession(jsonEncode(receipt));
      final gateway = CollectAdminRosterGateway(client);
      addTearDown(gateway.dispose);
      final invalidated = Completer<void>();
      final sub = gateway.invalidations.listen((_) {
        if (!invalidated.isCompleted) invalidated.complete();
      });
      addTearDown(sub.cancel);
      await invalidated.future.timeout(const Duration(seconds: 4));
      expect(gateway.ownerStillCurrent, isFalse);
      await client.auth.recoverSession(
        jsonEncode(_auth(nonce: 'newer')),
        event: CollectAuthEvent.tokenRefreshed,
      );
      expect(gateway.isCurrent, isFalse);
      await expectLater(gateway.read(adminReadTarget), throwsStateError);
    },
  );

  for (final signal in ['logout', 'signedOut notification', 'done']) {
    test('$signal denies gateway and request scope permanently', () async {
      final client = _client();
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(_auth()));
      final gateway = CollectAdminRosterGateway(client);
      final fence = AdminRequestSession(client);
      final controller = AdminSessionController(client);
      addTearDown(() async {
        gateway.dispose();
        controller.dispose();
        await fence.dispose();
      });
      if (signal == 'done') {
        await client.dispose();
      } else if (signal == 'logout') {
        await client.auth.clearLocalSession();
      } else {
        client.auth.notifyAllSubscribers(CollectAuthEvent.signedOut);
      }
      expect(controller.state, isNull);
      expect(gateway.isCurrent, isFalse);
      expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
      if (signal != 'done') {
        await client.auth.recoverSession(jsonEncode(_auth(nonce: 'newer')));
        expect(controller.state, isNotNull);
        expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
        expect(gateway.isCurrent, isFalse);
      }
    });
  }
  test(
    'controller changes generation after A-B-A and fresh SID, preserving sticky old fences',
    () async {
      final client = _client();
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(_auth()));
      final controller = AdminSessionController(client);
      final fence = AdminRequestSession(client);
      addTearDown(() async {
        controller.dispose();
        await fence.dispose();
      });
      final before = controller.state!.generation;
      for (final receipt in [
        _auth(actor: adminReadTarget, sid: _sidB),
        _auth(nonce: 'back'),
        _auth(sid: _sidB),
      ]) {
        await client.auth.recoverSession(jsonEncode(receipt));
      }
      expect(controller.state!.generation, before + 3);
      expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
    },
  );

  group('actual HTTP dispatch and awaited expiry', () {
    late CollectCloudflareClient client;
    late List<http.Request> requests;
    late FutureOr<http.Response> Function(http.Request) respond;
    Future<void> login(Map<String, dynamic> receipt) async {
      await client.auth.recoverSession(jsonEncode(receipt));
    }

    setUp(() async {
      requests = [];
      respond = (_) => _json({});
      client = CollectCloudflareClient(
        'http://127.0.0.1:1',
        httpClient: MockClient((r) async {
          if (r.url.path == '/v1/auth/refresh') {
            return _json({'error': 'unavailable'}, 503);
          }
          requests.add(r);
          final result = await respond(r);
          return http.Response.bytes(
            result.bodyBytes,
            result.statusCode,
            headers: result.headers,
            request: r,
          );
        }),
      );
      await login(_auth());
    });
    tearDown(() => client.dispose());
    for (final operation in [
      'prepare',
      'review',
      'commit',
      'read',
      'recovery',
    ]) {
      test(
        '$operation pins token and suppresses same-owner A-B-A late acknowledgement',
        () async {
          final gateway = CollectAdminRosterGateway(client);
          addTearDown(gateway.dispose);
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return _json({});
          };
          final token = client.auth.currentSession!.accessToken;
          final pending = switch (operation) {
            'prepare' => gateway.prepare({}),
            'review' => gateway.review({}),
            'commit' => gateway.commit({}),
            'read' => gateway.read(adminReadTarget),
            _ => gateway.recoveryRpc('admin_recover_roster_import', {}),
          };
          final assertion = expectLater(pending, throwsStateError);
          await started.future;
          await login(_auth(sid: _sidB));
          await login(_auth(nonce: 'back'));
          release.complete();
          await assertion;
          expect(requests.single.headers['Authorization'], 'Bearer $token');
          expect(gateway.isCurrent, isFalse);
        },
      );
    }
    test(
      'same-SID refresh while live preserves pinned request and updates later dispatch',
      () async {
        final gateway = CollectAdminRosterGateway(client);
        addTearDown(gateway.dispose);
        final started = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          if (!started.isCompleted) {
            started.complete();
            await release.future;
          }
          return _json({});
        };
        final token = client.auth.currentSession!.accessToken;
        final pending = gateway.read(adminReadTarget);
        await started.future;
        await login(_auth(nonce: 'refresh'));
        release.complete();
        await pending;
        expect(requests.first.headers['Authorization'], 'Bearer $token');
        await gateway.read(adminReadTarget);
        expect(
          requests.last.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
      },
    );
    for (final error in [false, true]) {
      test(
        'actual awaited response error=$error after expiry is suppressed',
        () async {
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
          await login(_auth(exp: expiry));
          final gateway = CollectAdminRosterGateway(client);
          addTearDown(gateway.dispose);
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return error
                ? _json({
                    'code': '42501',
                    'message': 'synthetic private expired response',
                  }, 403)
                : _json({});
          };
          final assertion = expectLater(
            gateway.read(adminReadTarget),
            throwsStateError,
          );
          await started.future;
          await Future<void>.delayed(
            DateTime.fromMillisecondsSinceEpoch(
                  expiry * 1000,
                ).difference(DateTime.now()) +
                const Duration(milliseconds: 50),
          );
          release.complete();
          await assertion;
          expect(gateway.isCurrent, isFalse);
          expect(requests, hasLength(1));
        },
      );
    }
    test('dispose is idempotent and denies further dispatch', () async {
      final gateway = CollectAdminRosterGateway(client);
      gateway.dispose();
      gateway.dispose();
      await expectLater(gateway.read(adminReadTarget), throwsStateError);
      expect(requests, isEmpty);
    });
  });
}
