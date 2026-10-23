import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object value) => http.Response(jsonEncode(value), 200);
Map<String, dynamic> session() {
  const id = '11111111-1111-4111-8111-111111111111';
  String encode(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900;
  return {
    'access_token':
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': id, 'session_id': '22222222-2222-4222-8222-222222222222', 'role': 'authenticated', 'exp': expiry, 'aal': 'aal1'})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'expires_in': 900,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': id,
      'email': 'member@gmail.com',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
}

void main() {
  test(
    'Google keeps PKCE in memory and adopts only the backend session',
    () async {
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        captchaProvider: () async => 'fresh-captcha',
        httpClient: MockClient((request) async {
          requests.add(request);
          return reply(
            request.url.path.endsWith('/start')
                ? {
                    'authorization_url':
                        'https://accounts.google.com/o/oauth2/v2/auth?client_id=controlled',
                  }
                : session(),
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithGoogle(
        authorize: (createUrl, state, origin) async {
          expect(origin, 'https://api.example.com');
          expect(
            (await createUrl('https://collect.example')).host,
            'accounts.google.com',
          );
          return {'state': state, 'code': 'a' * 43};
        },
      );
      expect(client.auth.currentUser?.email, 'member@gmail.com');
      expect(requests.map((r) => r.url.path), [
        '/v1/auth/google/start',
        '/v1/auth/google/exchange',
      ]);
      final start = jsonDecode(requests.first.body) as Map,
          exchange = jsonDecode(requests.last.body) as Map;
      expect(start['captcha_token'], 'fresh-captcha');
      expect(start['surface'], 'member');
      final verifier = exchange['code_verifier'] as String;
      expect(
        start['code_challenge'],
        base64UrlEncode(
          sha256.convert(utf8.encode(verifier)).bytes,
        ).replaceAll('=', ''),
      );
      expect(
        requests.every((r) => !r.url.toString().contains(verifier)),
        isTrue,
      );
    },
  );

  test(
    'Google cancellation and wrong callback state cannot create a session',
    () async {
      var exchanges = 0;
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/exchange')) exchanges++;
          return reply({
            'authorization_url': 'https://accounts.google.com/o/oauth2/v2/auth',
          });
        }),
      );
      addTearDown(client.dispose);
      for (final result in [
        {'error': 'google_cancelled'},
        {'state': 'wrong-state', 'code': 'a' * 43},
      ]) {
        await expectLater(
          client.auth.signInWithGoogle(
            authorize: (_, state, origin) async => result,
          ),
          throwsA(isA<CollectAuthException>()),
        );
        expect(client.auth.currentSession, isNull);
      }
      expect(exchanges, 0);
    },
  );

  test(
    'cancelling while Turnstile is pending prevents a late Google request',
    () async {
      final captcha = Completer<String>(), started = Completer<void>();
      var requests = 0;
      final client = CollectCloudflareClient(
        'https://api.example.com',
        captchaProvider: () {
          started.complete();
          return captcha.future;
        },
        httpClient: MockClient((r) async {
          requests++;
          return reply({});
        }),
      );
      addTearDown(client.dispose);
      final pending = client.auth.signInWithGoogle(
        authorize: (createUrl, state, origin) async {
          await createUrl(null);
          return {'state': state, 'code': 'a' * 43};
        },
      );
      await started.future;
      final expectation = expectLater(
        pending,
        throwsA(
          isA<CollectAuthException>().having(
            (e) => e.code,
            'reason',
            'session_changed',
          ),
        ),
      );
      client.auth.cancelGoogleSignIn();
      captcha.complete('fresh-captcha');
      await expectation;
      expect(requests, 0);
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'account change during Google exchange cannot install a late session',
    () async {
      final exchange = Completer<http.Response>(), started = Completer<void>();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/start')) {
            return reply({
              'authorization_url':
                  'https://accounts.google.com/o/oauth2/v2/auth',
            });
          }
          started.complete();
          return exchange.future;
        }),
      );
      addTearDown(client.dispose);
      final pending = client.auth.signInWithGoogle(
        authorize: (createUrl, state, origin) async {
          await createUrl(null);
          return {'state': state, 'code': 'a' * 43};
        },
      );
      await started.future;
      final expectation = expectLater(
        pending,
        throwsA(isA<CollectAuthException>()),
      );
      await client.auth.clearLocalSession();
      exchange.complete(reply(session()));
      await expectation;
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'Google refuses an untrusted authorization URL and Admin surface',
    () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient(
          (r) async =>
              reply({'authorization_url': 'https://evil.example/sign-in'}),
        ),
      );
      final admin = CollectCloudflareClient(
        'https://api.example.com',
        surface: 'admin',
      );
      addTearDown(client.dispose);
      addTearDown(admin.dispose);
      Future<Map<String, dynamic>> authorize(
        Future<Uri> Function(String?) createUrl,
        String state,
        String origin,
      ) async {
        await createUrl(null);
        return {};
      }

      await expectLater(
        client.auth.signInWithGoogle(authorize: authorize),
        throwsA(isA<CollectAuthException>()),
      );
      await expectLater(
        admin.auth.signInWithGoogle(authorize: authorize),
        throwsA(isA<CollectAuthException>()),
      );
      expect(client.auth.currentSession, isNull);
      expect(admin.auth.currentSession, isNull);
    },
  );
}
