import 'dart:convert';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/synthetic_jwt.dart';

const _actor = '12345678-1234-4234-8234-123456789012';
const _sid = '12345678-1234-4234-8234-123456789013';
Map<String, dynamic> _rawSession(
  int expiry, {
  String? role = 'authenticated',
}) => {
  'access_token': syntheticJwt(
    {'alg': 'HS256', 'typ': 'JWT'},
    {'sub': _actor, 'session_id': _sid, 'exp': expiry, 'role': ?role},
  ),
  'refresh_token': 'synthetic-only',
  'token_type': 'bearer',
  'user': {
    'id': _actor,
    'app_metadata': {},
    'user_metadata': {},
    'aud': 'authenticated',
  },
};
void main() {
  test('local JWT fence preserves expiry without asserting authentication', () {
    final session = CollectAuthSession.fromJson(_rawSession(1516239022))!;
    expect(session.claims['exp'], 1516239022);
    expect(session.isExpired, isTrue);
    expect(session.toString(), 'CollectAuthSession');
  });
  test('local shape cannot admit missing role or another subject', () {
    expect(
      CollectAuthSession.fromJson(_rawSession(4000000000, role: null)),
      isNull,
    );
    expect(
      CollectAuthSession.fromJson(
        _rawSession(4000000000, role: 'service_role'),
      ),
      isNull,
    );
    final wrong = {
      ..._rawSession(4000000000),
      'user': {
        'id': '12345678-1234-4234-8234-123456789099',
        'app_metadata': {},
        'user_metadata': {},
      },
    };
    expect(CollectAuthSession.fromJson(wrong), isNull);
  });
  test(
    'server rejection cannot authenticate unsigned fixture claims',
    () async {
      var verifyRequests = 0;
      final client = CollectCloudflareClient(
        'https://claims-fixture.example.invalid',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/otp') {
            return http.Response(
              jsonEncode({'challenge_id': 'fixture-challenge'}),
              200,
            );
          }
          expect(request.url.path, '/v1/auth/verify');
          verifyRequests++;
          return http.Response(jsonEncode({'code': 'otp_invalid'}), 401);
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
        throwsA(isA<CollectAuthException>()),
      );
      expect(verifyRequests, 1);
      expect(client.auth.currentSession, isNull);
    },
  );
}
