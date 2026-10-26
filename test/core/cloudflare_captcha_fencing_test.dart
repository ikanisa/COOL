import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _receipt() {
  const user = '12345678-1234-4234-8234-123456789012';
  final claims = {
    'sub': user,
    'session_id': '12345678-1234-4234-8234-123456789013',
    'role': 'authenticated',
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  };
  return {
    'access_token':
        'e30.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.synthetic',
    'refresh_token': 'SYNTHETIC_REFRESH',
    'token_type': 'bearer',
    'user': {'id': user, 'app_metadata': {}, 'user_metadata': {}},
  };
}

void main() {
  test(
    'send and verify acquire separate candidates; server receives each once',
    () async {
      var challenges = 0;
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://synthetic.invalid',
        captchaProvider: () async => 'SYNTHETIC_CANDIDATE_${++challenges}',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/otp')
                  ? {'challenge_id': 'synthetic-challenge'}
                  : _receipt(),
            ),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithOtp(
        phone: '+250788000001',
        captchaToken: 'CALLER_OLD_CANDIDATE',
      );
      await client.auth.verifyOTP(
        phone: '+250788000001',
        token: '123456',
        type: CollectOtpType.sms,
        captchaToken: 'CALLER_OLD_CANDIDATE',
      );
      expect(challenges, 2);
      expect(requests.map((r) => jsonDecode(r.body)['captcha_token']), [
        'SYNTHETIC_CANDIDATE_1',
        'SYNTHETIC_CANDIDATE_2',
      ]);
      expect(requests.map((r) => r.url.path), [
        '/v1/auth/otp',
        '/v1/auth/verify',
      ]);
    },
  );

  test(
    'failed challenge does not dispatch, install or retry authentication',
    () async {
      var requests = 0;
      final client = CollectCloudflareClient(
        'https://synthetic.invalid',
        captchaProvider: () async =>
            throw StateError('SYNTHETIC_PROVIDER_SECRET'),
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.auth.signInWithOtp(phone: '+250788000001'),
        throwsA(
          isA<CollectAuthException>().having(
            (e) => e.toString(),
            'safe failure',
            isNot(contains('SYNTHETIC_PROVIDER_SECRET')),
          ),
        ),
      );
      expect(requests, 0);
      expect(client.auth.currentSession, isNull);
    },
  );

  test('logout while challenge is open prevents a late OTP send', () async {
    final started = Completer<void>(), candidate = Completer<String>();
    var requests = 0, cancelled = 0;
    final client = CollectCloudflareClient(
      'https://synthetic.invalid',
      captchaProvider: () {
        started.complete();
        return candidate.future;
      },
      cancelCaptcha: () {
        cancelled++;
      },
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    final sending = client.auth.signInWithOtp(phone: '+250788000001');
    final assertion = expectLater(
      sending,
      throwsA(isA<CollectAuthException>()),
    );
    await started.future;
    await client.auth.clearLocalSession();
    candidate.complete('SYNTHETIC_LATE_CANDIDATE');
    await assertion;
    expect(cancelled, 1);
    expect(requests, 0);
    expect(client.auth.currentSession, isNull);
  });
}
