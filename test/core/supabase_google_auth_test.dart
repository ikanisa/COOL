import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'supabase_backend_test.dart' as fixtures;

Uri authorizeUrl({
  String? redirect,
  String? provider,
}) => Uri.parse('${fixtures.project}/auth/v1/authorize').replace(
  queryParameters: {
    'provider': provider ?? 'google',
    'redirect_to':
        redirect ??
        '$collectSupabaseGoogleCallbackOrigin/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}',
    'code_challenge': 'b' * 43,
    'code_challenge_method': 's256',
    'scopes': 'openid email profile',
    'prompt': 'select_account',
  },
);

void main() {
  test(
    'managed callback admission isolates explicitly selected QA and production',
    () {
      final qa = authorizeUrl(
        redirect:
            '$collectSupabaseGoogleQaCallbackOrigin/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}',
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(qa, usesSupabase: true),
        isFalse,
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(
          qa,
          usesSupabase: true,
          supabaseCallbackOrigin: collectSupabaseGoogleQaCallbackOrigin,
        ),
        isTrue,
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(
          authorizeUrl(),
          usesSupabase: true,
          supabaseCallbackOrigin: collectSupabaseGoogleQaCallbackOrigin,
        ),
        isFalse,
      );
      for (final selected in [
        'https://unapproved.invalid',
        '$collectSupabaseGoogleQaCallbackOrigin.evil.invalid',
        '$collectSupabaseGoogleQaCallbackOrigin:444',
        'http://admin-supabase-qa.collect.ikanisa.com',
      ]) {
        expect(
          collectGoogleAuthorizationUrlAllowed(
            qa,
            usesSupabase: true,
            supabaseCallbackOrigin: selected,
          ),
          isFalse,
        );
      }
      for (final candidate in [
        Uri.parse(
          '${qa.toString()}&redirect_to=${Uri.encodeComponent('https://unapproved.invalid')}',
        ),
        Uri.parse('${qa.toString()}&code_challenge_method=s256'),
        authorizeUrl(
          redirect:
              '$collectSupabaseGoogleQaCallbackOrigin/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}&state=${'b' * 43}',
        ),
        qa.replace(fragment: 'tokens'),
        qa.replace(host: 'unapproved.supabase.co'),
      ]) {
        expect(
          collectGoogleAuthorizationUrlAllowed(
            candidate,
            usesSupabase: true,
            supabaseCallbackOrigin: collectSupabaseGoogleQaCallbackOrigin,
          ),
          isFalse,
        );
      }
      expect(
        collectSupabaseGoogleCallbackOriginForApi(Uri.parse(fixtures.project)),
        collectSupabaseGoogleCallbackOrigin,
      );
      for (final api in [
        'https://unapproved.invalid',
        'https://user@admin-supabase-qa.collect.ikanisa.com',
        '$collectSupabaseGoogleQaCallbackOrigin#tokens',
      ]) {
        expect(
          collectSupabaseGoogleCallbackOriginForApi(Uri.parse(api)),
          isNull,
        );
      }
    },
  );

  test(
    'QA member uses only its configured callback and preserves member session mapping',
    () async {
      const qa = 'https://admin-supabase-qa.collect.ikanisa.com';
      final calls = <http.Request>[];
      final config = CollectSupabaseConfiguration.fromEnvironment(
        fixtures.environment(api: qa),
      );
      late String clientState;
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          calls.add(request);
          expect(request.url.origin, qa);
          final body = jsonDecode(request.body) as Map;
          if (request.url.path.endsWith('/google/start')) {
            clientState = body['client_state'] as String;
            expect(body['surface'], 'member');
            return http.Response(
              jsonEncode({
                'authorization_url': authorizeUrl(
                  redirect:
                      '$qa/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}',
                ).toString(),
              }),
              200,
            );
          }
          expect(
            request.url.path,
            '/functions/v1/collect-api/v1/auth/google/exchange',
          );
          expect(body['client_state'], clientState);
          expect(body['code_verifier'], matches(r'^[A-Za-z0-9_-]{43}$'));
          return http.Response(jsonEncode(fixtures.session()), 200);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      await client.auth.signInWithGoogle(
        authorize: (createUrl, state, callbackOrigin) async {
          expect(callbackOrigin, qa);
          await createUrl(null);
          expect(state, clientState);
          return {'code': 'c' * 43, 'state': state};
        },
      );
      expect(calls.length, 2);
      expect(client.auth.currentUser?.id, fixtures.principal);
      expect(client.auth.currentSession?.claims['sub'], fixtures.authUser);
    },
  );

  test(
    'unapproved member API cannot originate managed Google authorization',
    () async {
      var calls = 0;
      final config = CollectSupabaseConfiguration.fromEnvironment(
        fixtures.environment(api: 'https://unapproved.invalid'),
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      await expectLater(
        client.auth.signInWithGoogle(
          authorize: (_, _, _) async {
            fail('Unapproved API must not open authorization.');
          },
        ),
        throwsA(isA<CollectAuthException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'managed Google authorize URL accepts only nominated provider and callback controls',
    () {
      final valid = authorizeUrl();
      expect(
        collectGoogleAuthorizationUrlAllowed(valid, usesSupabase: true),
        isTrue,
      );
      for (final candidate in [
        valid.replace(host: 'other.supabase.co'),
        valid.replace(port: 444),
        valid.replace(userInfo: 'attacker'),
        valid.replace(fragment: 'tokens'),
        Uri.parse('${valid.toString()}&provider=google'),
        Uri.parse('${valid.toString()}&redirect_to=https%3A%2F%2Fevil.invalid'),
        Uri.parse('${valid.toString()}&unknown=control'),
        authorizeUrl(provider: 'github'),
        authorizeUrl(
          redirect: 'https://evil.invalid/callback?state=${'a' * 43}',
        ),
        authorizeUrl(redirect: '/relative?state=${'a' * 43}'),
        authorizeUrl(
          redirect:
              '$collectSupabaseGoogleCallbackOrigin/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}&state=${'b' * 43}',
        ),
        Uri.parse('https:/malformed'),
      ]) {
        expect(
          collectGoogleAuthorizationUrlAllowed(candidate, usesSupabase: true),
          isFalse,
          reason: candidate.toString(),
        );
      }
      final legacy = Uri.parse(
        'https://accounts.google.com/o/oauth2/v2/auth?state=legacy',
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(legacy, usesSupabase: false),
        isTrue,
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(legacy, usesSupabase: true),
        isFalse,
      );
      expect(
        collectGoogleAuthorizationUrlAllowed(valid, usesSupabase: false),
        isFalse,
      );
    },
  );

  test(
    'member Google uses managed authorize hop, fixed callback origin and mapped session',
    () async {
      final calls = <http.Request>[];
      late String clientState;
      final config = CollectSupabaseConfiguration.fromEnvironment(
        fixtures.environment(),
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          calls.add(request);
          final body = jsonDecode(request.body) as Map;
          if (request.url.path.endsWith('/google/start')) {
            clientState = body['client_state'] as String;
            expect(body['surface'], 'member');
            return http.Response(
              jsonEncode({'authorization_url': authorizeUrl().toString()}),
              200,
            );
          }
          expect(
            request.url.path,
            '/functions/v1/collect-api/v1/auth/google/exchange',
          );
          expect(body['client_state'], clientState);
          expect(body['code_verifier'], matches(r'^[A-Za-z0-9_-]{43}$'));
          return http.Response(jsonEncode(fixtures.session()), 200);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      await client.auth.signInWithGoogle(
        authorize: (createUrl, state, callbackOrigin) async {
          expect(callbackOrigin, collectSupabaseGoogleCallbackOrigin);
          final url = await createUrl(null);
          expect(url.origin, fixtures.project);
          expect(state, clientState);
          return {'code': 'c' * 43, 'state': state};
        },
      );
      expect(calls.length, 2);
      expect(client.auth.currentUser?.id, fixtures.principal);
      expect(client.auth.currentSession?.claims['sub'], fixtures.authUser);
    },
  );

  test(
    'successful unknown OTP delivery preserves challenge for explicit verification',
    () async {
      final calls = <http.Request>[];
      final config = CollectSupabaseConfiguration.fromEnvironment(
        fixtures.environment(),
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/auth/otp')) {
            return http.Response(
              jsonEncode({
                'challenge_id': 'fixture-pending',
                'retry_after': 60,
                'delivery_status': 'unknown',
              }),
              200,
            );
          }
          expect(
            (jsonDecode(request.body) as Map)['challenge_id'],
            'fixture-pending',
          );
          return http.Response(jsonEncode(fixtures.session()), 200);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      await expectLater(
        client.auth.signInWithOtp(email: 'member@example.invalid'),
        throwsA(isA<CollectOtpDeliveryUnknownException>()),
      );
      await client.auth.verifyOTP(
        email: 'member@example.invalid',
        token: '123456',
        type: CollectOtpType.email,
      );
      expect(calls.length, 2);
      expect(client.auth.currentUser?.id, fixtures.principal);
    },
  );
}
