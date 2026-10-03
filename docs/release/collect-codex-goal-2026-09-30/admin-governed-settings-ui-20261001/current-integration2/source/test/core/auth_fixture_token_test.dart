import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../third_party/gotrue/test/synthetic_jwt.dart';

void main() {
  test('unsigned fixture preserves expiry and is rejected as expired', () {
    final token = syntheticJwt(
      {'alg': 'HS256', 'typ': 'JWT'},
      {'sub': '1234567890', 'exp': 1516239022},
    );
    final decoded = decodeJwt(token);
    expect(decoded.header.alg, 'HS256');
    expect(decoded.payload.sub, '1234567890');
    expect(decoded.payload.exp, 1516239022);
    expect(
      () => validateExp(decoded.payload.exp),
      throwsA(isA<AuthException>()),
    );
  });

  test('unsigned fixture preserves SDK parser claims without a session', () {
    final token = syntheticJwt(
      {'alg': 'HS256', 'typ': 'JWT', 'kid': 'test-kid'},
      {
        'sub': '1234567890',
        'name': 'John Doe',
        'iat': 1516239022,
        'exp': 9999999999,
      },
    );
    final decoded = decodeJwt(token);
    expect(decoded.header.kid, 'test-kid');
    expect(decoded.payload.claims['name'], 'John Doe');
    expect(decoded.payload.iat, 1516239022);
    expect(decoded.payload.exp, 9999999999);
    expect(() => validateExp(decoded.payload.exp), returnsNormally);
  });

  test(
    'asymmetric fixture requests JWKS and never authenticates dummy bytes',
    () async {
      var jwksRequests = 0;
      final client = GoTrueClient(
        url: 'https://claims-fixture.example.invalid/auth/v1',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/.well-known/jwks.json');
          jwksRequests += 1;
          return http.Response(
            jsonEncode({'keys': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final token = syntheticJwt(
        {'alg': 'RS256', 'typ': 'JWT', 'kid': 'test-key-id'},
        {
          'sub': '1234567890',
          'aud': 'authenticated',
          'exp': 9999999999,
          'iat': 1516239022,
          'email': 'parser@example.invalid',
          'role': 'authenticated',
        },
      );
      await expectLater(client.getClaims(token), throwsA(isA<AuthException>()));
      expect(jwksRequests, 1);
      expect(client.currentSession, isNull);
    },
  );
}
