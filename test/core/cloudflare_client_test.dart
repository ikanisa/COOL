import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const _actor = '11111111-1111-4111-8111-111111111111';
const _session = '22222222-2222-4222-8222-222222222222';
const _otherActor = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> _credentials({
  String actor = _actor,
  String session = _session,
  String refresh = 'opaque-refresh',
}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return {
    'access_token':
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': actor, 'session_id': session, 'role': 'authenticated', 'exp': expiry, 'aal': 'aal1'})}.test-signature',
    'refresh_token': refresh,
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': actor,
      'phone': '+250788123456',
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
    },
  };
}

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('only HTTPS origins and explicit scoped read contracts are allowed', () {
    for (final origin in [
      'http://example.com',
      'https://a:b@example.com',
      'https://example.com/path',
      'https://example.com?x=1',
    ]) {
      expect(() => CollectCloudflareClient(origin), throwsArgumentError);
    }
    final client = CollectCloudflareClient('https://api.example.com');
    addTearDown(client.dispose);
    expect(() => client.from('profiles'), throwsArgumentError);
    expect(() => client.rpc('../secrets'), throwsArgumentError);
    expect(
      () => client.from('notification_events').limit(101),
      throwsArgumentError,
    );
  });

  test(
    'OTP challenge is bound to identity and installs only a valid session',
    () async {
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        surface: 'admin',
        httpClient: MockClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/otp')
              ? _json({'challenge_id': 'verified-challenge'})
              : _json(_credentials());
        }),
      );
      addTearDown(client.dispose);
      final requestReceipt = await client.auth.signInWithOtp(
        email: 'operator@example.com',
      );
      expect(requestReceipt.retryAfterSeconds, 60);
      await client.auth.verifyOTP(
        email: 'operator@example.com',
        token: '123456',
        type: CollectOtpType.email,
      );
      expect(client.auth.currentUser?.id, _actor);
      expect(requests.map((r) => r.url.path), [
        '/v1/auth/otp',
        '/v1/auth/verify',
      ]);
      final verify = jsonDecode(requests.last.body) as Map;
      expect(verify['challenge_id'], 'verified-challenge');
      expect(verify['code'], '123456');
      expect(verify['surface'], 'admin');
      expect(requests.every((r) => !r.headers.containsKey('apikey')), isTrue);
      await expectLater(
        client.auth.verifyOTP(
          phone: '+250788999999',
          token: '123456',
          type: CollectOtpType.sms,
        ),
        throwsA(isA<CollectAuthException>()),
      );
      expect(requests.length, 2);
    },
  );

  test(
    'uncertain OTP delivery retains its bound challenge for verification without another send',
    () async {
      final calls = <http.Request>[];
      var captchaCalls = 0;
      final client = CollectCloudflareClient(
        'https://api.example.com',
        captchaProvider: () async => 'controlled-captcha-${++captchaCalls}',
        httpClient: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/otp')) {
            return _json({
              'error': {
                'code': 'otp_delivery_unknown',
                'message': 'Private upstream text',
              },
              'challenge_id': _session,
              'request_id': _session,
              'retry_after': 120,
            }, 503);
          }
          return _json(_credentials());
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.auth.signInWithOtp(phone: '+250788123456'),
        throwsA(
          isA<CollectOtpDeliveryUnknownException>().having(
            (e) => e.retryAfterSeconds,
            'cooldown',
            120,
          ),
        ),
      );
      expect(client.auth.currentSession, isNull);
      await client.auth.verifyOTP(
        phone: '+250788123456',
        token: '123456',
        type: CollectOtpType.sms,
      );
      expect(calls.where((r) => r.url.path.endsWith('/otp')), hasLength(1));
      expect((jsonDecode(calls.last.body) as Map)['challenge_id'], _session);
      expect(client.auth.currentUser?.id, _actor);
      expect(captchaCalls, 2);
      expect(
        (jsonDecode(calls.first.body) as Map)['captcha_token'],
        'controlled-captcha-1',
      );
      expect(
        (jsonDecode(calls.last.body) as Map)['captcha_token'],
        'controlled-captcha-2',
      );
    },
  );
  for (final defect in ['challenge', 'request', 'cooldown', 'status']) {
    test(
      'an invalid delivery-unknown reply cannot create a verification capability: $defect',
      () async {
        var calls = 0;
        final reply = <String, dynamic>{
          'error': {'code': 'otp_delivery_unknown'},
          'challenge_id': _session,
          'request_id': _session,
          'retry_after': 60,
        };
        if (defect == 'challenge') reply['challenge_id'] = 'not-a-challenge';
        if (defect == 'request') reply['request_id'] = _otherActor;
        if (defect == 'cooldown') reply['retry_after'] = 0;
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: MockClient((r) async {
            calls++;
            return _json(reply, defect == 'status' ? 429 : 503);
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.auth.signInWithOtp(phone: '+250788123456'),
          throwsA(isA<CollectAuthException>()),
        );
        await expectLater(
          client.auth.verifyOTP(
            phone: '+250788123456',
            token: '123456',
            type: CollectOtpType.sms,
          ),
          throwsA(
            isA<CollectAuthException>().having(
              (e) => e.code,
              'no retained challenge',
              'invalid_challenge',
            ),
          ),
        );
        expect(calls, 1);
        expect(client.auth.currentSession, isNull);
      },
    );
  }
  for (final retry in [59, 3601, '120']) {
    test(
      'malformed accepted-request cooldown cannot install a challenge: $retry',
      () async {
        var calls = 0;
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: MockClient((r) async {
            calls++;
            return _json({'challenge_id': _session, 'retry_after': retry}, 202);
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.auth.signInWithOtp(phone: '+250788123456'),
          throwsA(
            isA<CollectAuthException>().having(
              (e) => e.code,
              'malformed receipt',
              'invalid_response',
            ),
          ),
        );
        await expectLater(
          client.auth.verifyOTP(
            phone: '+250788123456',
            token: '123456',
            type: CollectOtpType.sms,
          ),
          throwsA(
            isA<CollectAuthException>().having(
              (e) => e.code,
              'no challenge',
              'invalid_challenge',
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }
  test(
    'a late uncertain send cannot replace the newer bound challenge',
    () async {
      final first = Completer<http.Response>();
      final calls = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((r) async {
          calls.add(r);
          if (calls.length == 1) return first.future;
          if (r.url.path.endsWith('/otp')) {
            return _json({'challenge_id': 'newer-challenge'});
          }
          return _json(_credentials());
        }),
      );
      addTearDown(client.dispose);
      final older = client.auth.signInWithOtp(phone: '+250788123456');
      final olderExpectation = expectLater(
        older,
        throwsA(
          isA<CollectAuthException>().having(
            (e) => e.code,
            'originating operation',
            'session_changed',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await client.auth.signInWithOtp(phone: '+250788123456');
      first.complete(
        _json({
          'error': {'code': 'otp_delivery_unknown'},
          'challenge_id': _session,
          'request_id': _session,
          'retry_after': 60,
        }, 503),
      );
      await olderExpectation;
      await client.auth.verifyOTP(
        phone: '+250788123456',
        token: '123456',
        type: CollectOtpType.sms,
      );
      expect(
        (jsonDecode(calls.last.body) as Map)['challenge_id'],
        'newer-challenge',
      );
    },
  );
  test('late OTP verification cannot overwrite a switched account', () async {
    final verifyReply = Completer<http.Response>();
    final client = CollectCloudflareClient(
      'https://api.example.com',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/otp')) {
          return _json({'challenge_id': 'challenge'});
        }
        return verifyReply.future;
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithOtp(phone: '+250788123456');
    final verifying = client.auth.verifyOTP(
      phone: '+250788123456',
      token: '123456',
      type: CollectOtpType.sms,
    );
    await Future<void>.delayed(Duration.zero);
    await client.auth.recoverSession(
      jsonEncode(_credentials(actor: _otherActor)),
    );
    verifyReply.complete(_json(_credentials()));
    await expectLater(verifying, throwsA(isA<CollectAuthException>()));
    expect(client.auth.currentUser?.id, _otherActor);
  });

  test(
    'a captured RPC executes once and never retries uncertain writes',
    () async {
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _json({'code': 'provider_unavailable'}, 503);
        }),
      );
      addTearDown(client.dispose);
      final original = _credentials();
      await client.auth.recoverSession(jsonEncode(original));
      final operation = client
          .rpc<dynamic>(
            'create_collection',
            params: {'request_id': 'same-request'},
          )
          .setHeader('Authorization', 'Bearer ${original['access_token']}')
          .retry(enabled: false);
      await client.auth.recoverSession(
        jsonEncode(_credentials(actor: _otherActor)),
      );
      await expectLater(operation, throwsA(isA<CollectApiException>()));
      await expectLater(operation, throwsA(isA<CollectApiException>()));
      expect(requests.length, 1);
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${original['access_token']}',
      );
      expect(jsonDecode(requests.single.body)['request_id'], 'same-request');
    },
  );

  test(
    'logout clears memory synchronously and revokes the captured session',
    () async {
      final logoutReply = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((request) async {
          requests.add(request);
          return logoutReply.future;
        }),
      );
      addTearDown(client.dispose);
      final original = _credentials();
      await client.auth.recoverSession(jsonEncode(original));
      final events = <CollectAuthState>[];
      final subscription = client.auth.onAuthStateChangeSync.listen(events.add);
      addTearDown(subscription.cancel);
      final signingOut = client.auth.signOut();
      expect(client.auth.currentSession, isNull);
      expect(events.single.event, CollectAuthEvent.signedOut);
      await client.auth.recoverSession(
        jsonEncode(_credentials(actor: _otherActor)),
      );
      logoutReply.complete(_json({'ok': true}));
      await signingOut;
      expect(client.auth.currentUser?.id, _otherActor);
      expect(requests.single.url.path, '/v1/auth/logout');
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${original['access_token']}',
      );
    },
  );

  test(
    'refresh cannot replace another account or another session identity',
    () async {
      final reply = Completer<http.Response>();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((_) => reply.future),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(_credentials()));
      final refreshing = client.auth.refreshSession();
      await client.auth.recoverSession(
        jsonEncode(_credentials(actor: _otherActor)),
      );
      reply.complete(_json(_credentials(refresh: 'rotated-refresh')));
      await expectLater(refreshing, throwsA(isA<CollectAuthException>()));
      expect(client.auth.currentUser?.id, _otherActor);
    },
  );

  test(
    'redirects and oversized responses never become accepted reads',
    () async {
      for (final response in [
        http.Response(
          '',
          302,
          headers: {'location': 'https://other.example.com'},
        ),
        http.Response(
          'x' * (CollectCloudflareClient.maximumResponseBytes + 1),
          200,
        ),
      ]) {
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: MockClient((request) async {
            expect(request.followRedirects, isFalse);
            return response;
          }),
        );
        await expectLater(
          client.from('public_collections_view').select(),
          throwsA(isA<CollectApiException>()),
        );
        await client.dispose();
      }
    },
  );

  test(
    'native protected persistence failure invalidates accepted memory',
    () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: _FailingStorage(),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.auth.recoverSession(jsonEncode(_credentials())),
        throwsA(isA<CollectAuthException>()),
      );
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'credential DTOs and errors never print tokens or private account data',
    () {
      final session = CollectAuthSession.fromJson(_credentials())!;
      expect(session.toString(), 'CollectAuthSession');
      expect(session.user.toString(), 'CollectAuthUser');
      final error = collectApiFailure(500, {
        'code': 'backend_failure',
        'message': session.accessToken,
      });
      expect(error.message, 'Collect could not complete this request.');
      expect(error.toString(), isNot(contains(session.accessToken)));
      final malformed = {
        ..._credentials(),
        'user': {'id': 'unbound'},
      };
      expect(CollectAuthSession.fromJson(malformed), isNull);
    },
  );

  test(
    'actual nested auth failures preserve recovery reasons and HTTP status',
    () async {
      for (final entry in const {
        'captcha_failed': 400,
        'otp_delivery_unavailable': 503,
        'auth_rate_limited': 429,
      }.entries) {
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/v1/auth/otp');
            return _json({
              'error': {
                'code': entry.key,
                'message': 'PRIVATE_CANARY private@example.invalid',
              },
            }, entry.value);
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.auth.signInWithOtp(email: 'member@example.com'),
          throwsA(
            isA<CollectAuthException>()
                .having((error) => error.code, 'reason', entry.key)
                .having(
                  (error) => error.statusCode,
                  'HTTP status',
                  '${entry.value}',
                )
                .having(
                  (error) => error.message,
                  'safe message',
                  'Collect could not complete this request.',
                ),
          ),
        );
        expect(client.auth.currentSession, isNull);
      }
    },
  );

  test(
    'flat operating errors and malformed nested errors retain safe behavior',
    () {
      expect(
        collectApiFailure(503, {'code': 'otp_delivery_unavailable'}).code,
        'otp_delivery_unavailable',
      );
      for (final error in [
        {
          'error': ['PRIVATE_CANARY'],
        },
        {
          'error': {'code': 'PRIVATE_CANARY private@example.invalid'},
        },
        {
          'error': {'code': 401, 'message': 'PRIVATE_CANARY'},
        },
      ]) {
        final failure = collectApiFailure(503, error);
        expect(failure.code, '503');
        expect(failure.message, 'Collect could not complete this request.');
        expect(failure.toString(), isNot(contains('PRIVATE_CANARY')));
      }
    },
  );

  test(
    'a nested verification rejection leaves the challenge retryable',
    () async {
      var verificationRequests = 0;
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/otp')) {
            return _json({'challenge_id': 'retained-challenge'});
          }
          expect(
            jsonDecode(request.body)['challenge_id'],
            'retained-challenge',
          );
          verificationRequests++;
          return verificationRequests == 1
              ? _json({
                  'error': {'code': 'captcha_failed'},
                }, 400)
              : _json(_credentials());
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithOtp(phone: '+250788123456');
      await expectLater(
        client.auth.verifyOTP(
          phone: '+250788123456',
          token: '123456',
          type: CollectOtpType.sms,
        ),
        throwsA(
          isA<CollectAuthException>().having(
            (error) => error.code,
            'reason',
            'captcha_failed',
          ),
        ),
      );
      expect(client.auth.currentSession, isNull);
      await client.auth.verifyOTP(
        phone: '+250788123456',
        token: '123456',
        type: CollectOtpType.sms,
      );
      expect(verificationRequests, 2);
      expect(client.auth.currentUser?.id, _actor);
    },
  );
}

final class _FailingStorage implements CollectAuthSessionStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async => throw StateError('Key unavailable');
  @override
  Future<void> clear() async {}
}
