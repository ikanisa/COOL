import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile_contract.dart';
import 'package:collect_app/core/startup/collect_startup_controller.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const project = 'https://rrlduytparvsjfmegalh.supabase.co';
const principal = '00000000-0000-4000-8000-000000000011';
const authUser = '00000000-0000-4000-8000-000000000012';
const publishable = 'sb_publishable_synthetic_test_key_only';

AppEnv environment({
  String backend = 'supabase',
  String url = project,
  String api = '',
  String admin = 'https://backend.collect.ikanisa.com',
  String key = publishable,
  bool captcha = false,
}) => AppEnv(
  apiUrl: 'https://api.collect.ikanisa.com',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: false,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: captcha,
  authCaptchaProvider: 'turnstile',
  authCaptchaSiteKey: '',
  backend: backend,
  supabaseUrl: url,
  supabaseApiUrl: api,
  supabaseAdminApiUrl: admin,
  supabasePublishableKey: key,
);

Map<String, dynamic> session({
  String issuer = '$project/auth/v1',
  bool mapped = true,
}) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${part({'alg': 'ES256'})}.${part({'sub': mapped ? authUser : principal, 'iss': issuer, 'aud': 'authenticated', 'role': 'authenticated', 'session_id': '00000000-0000-4000-8000-000000000013', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
  return {
    'access_token': token,
    'refresh_token': 'fixture-refresh',
    'token_type': 'bearer',
    'user': {
      'id': principal,
      'phone': '+250788000001',
      if (mapped) 'auth_user_id': authUser,
    },
  };
}

void main() {
  test(
    'environment defaults select Supabase',
    () {
      expect(AppEnv.fromEnvironment().backend, 'supabase');
    },
    skip: const bool.hasEnvironment('COLLECT_BACKEND'),
  );

  test(
    'missing default configuration never falls back to a legacy API',
    () async {
      const unconfigured = AppEnv(
        apiUrl: 'https://legacy-fixture.invalid',
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
      );
      expect(unconfigured.backend, 'supabase');
      expect(unconfigured.usesSupabase, isTrue);
      expect(unconfigured.hasBackendConfig, isTrue);
      await expectLater(
        createCollectBackendClientFromEnvironment(environment: unconfigured),
        throwsA(isA<CollectStartupFailure>()),
      );
      for (final incomplete in [
        environment(url: '', key: publishable),
        environment(url: project, key: ''),
      ]) {
        await expectLater(
          createCollectBackendClientFromEnvironment(environment: incomplete),
          throwsA(isA<CollectStartupFailure>()),
        );
      }
    },
  );

  test(
    'explicit configuration refuses secret keys, paths and cross-site Admin',
    () {
      expect(
        () => CollectSupabaseConfiguration.fromEnvironment(
          environment(key: 'sb_secret_private'),
        ),
        throwsArgumentError,
      );
      expect(
        () => CollectSupabaseConfiguration.fromEnvironment(
          environment(url: '$project/auth/v1'),
        ),
        throwsArgumentError,
      );
      expect(
        () => CollectSupabaseConfiguration.fromEnvironment(
          environment(captcha: true),
        ),
        throwsArgumentError,
      );
      final config = CollectSupabaseConfiguration.fromEnvironment(
        environment(admin: project),
      );
      expect(
        () => config.adminRequest(
          'auth/session',
          browserOrigin: Uri.parse('https://admin.collect.ikanisa.com'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'project session namespaces are distinct and paths stay inside Functions',
    () {
      final config = CollectSupabaseConfiguration.fromEnvironment(
        environment(),
      );
      final other = CollectSupabaseConfiguration.fromEnvironment(
        environment(url: 'https://other-project.supabase.co'),
      );
      expect(config.storageOwner, isNot(other.storageOwner));
      expect(
        config.storageOwner,
        isNot('00000000-0000-4000-8000-000000000001'),
      );
      expect(
        () => config.adminRequest(
          '../auth/session',
          browserOrigin: Uri.parse('https://admin.collect.ikanisa.com'),
        ),
        throwsArgumentError,
      );
      expect(
        collectChallengeUri(
          '00000000-0000-4000-8000-000000000099',
          'https://collect.ikanisa.com',
          endpoint: Uri.parse(
            'https://backend.collect.ikanisa.com/functions/v1/collect-api/v1/security/challenge',
          ),
        ).path,
        '/functions/v1/collect-api/v1/security/challenge',
      );
    },
  );

  test(
    'Supabase OTP and operations keep stable principals with real identity tokens',
    () async {
      final calls = <http.Request>[];
      final config = CollectSupabaseConfiguration.fromEnvironment(
        environment(),
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/auth/otp')) {
            return http.Response(
              jsonEncode({
                'challenge_id': 'fixture-challenge',
                'retry_after': 60,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/auth/verify')) {
            return http.Response(jsonEncode(session()), 200);
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      await client.auth.signInWithOtp(
        phone: '+250788000001',
        channel: CollectOtpChannel.whatsapp,
        shouldCreateUser: false,
      );
      await client.auth.verifyOTP(
        phone: '+250788000001',
        token: '123456',
        type: CollectOtpType.sms,
      );
      await client.rpc<Map<String, dynamic>>('member_profile');
      expect(client.auth.currentUser?.id, principal);
      expect(client.auth.currentSession?.claims['sub'], authUser);
      expect(
        calls.every((request) => request.headers['apikey'] == publishable),
        isTrue,
      );
      expect(
        calls.last.url.path,
        '/functions/v1/collect-api/v1/rpc/member_profile',
      );
      expect(calls.last.headers['authorization'], startsWith('Bearer '));
      final otp = jsonDecode(calls.first.body) as Map;
      expect(otp['should_create_user'], isFalse);
      expect(otp['channel'], 'whatsapp');
    },
  );

  test(
    'foreign issuer and legacy credentials never enter a Supabase session',
    () async {
      final store = CollectMemorySessionStorage();
      await store.write(jsonEncode(session(issuer: 'collect-platform-api')));
      var requests = 0;
      final config = CollectSupabaseConfiguration.fromEnvironment(
        environment(),
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        sessionStorage: store,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      addTearDown(client.dispose);
      await client.initialize();
      expect(client.auth.currentSession, isNull);
      expect(await store.read(), isNull);
      expect(requests, 0);
      expect(
        () => client.auth.recoverSession(
          jsonEncode(session(issuer: 'https://foreign.invalid/auth/v1')),
        ),
        throwsA(isA<CollectAuthException>()),
      );
      expect(CollectAuthSession.fromJson(session()), isNull);
    },
  );

  test(
    'explicit legacy client fixture retains its route and headers',
    () async {
      late http.Request sent;
      final client = CollectCloudflareClient(
        'https://api.collect.ikanisa.com',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await client.rpc<Map<String, dynamic>>('member_profile');
      expect(sent.url.path, '/v1/rpc/member_profile');
      expect(sent.headers.containsKey('apikey'), isFalse);
    },
  );

  test(
    'privacy re-verification preserves principal fencing and never registers an account',
    () async {
      final config = CollectSupabaseConfiguration.fromEnvironment(
        environment(),
      );
      final captured = PrivacySessionSnapshot.parse(
        CollectAuthSession.fromJson(
          session(),
          allowMappedAuthUser: true,
          expectedIssuer: '$project/auth/v1',
        ),
        1,
      )!;
      expect(captured.subjectId, principal);
      final calls = <http.Request>[];
      final transport = CollectPrivacyRequestTransport(
        apiUrl: project,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/auth/otp')
                  ? {'challenge_id': 'privacy-fixture'}
                  : session(),
            ),
            200,
          );
        }),
      );
      await transport.sendCode(captured);
      final verified = await transport.verifyCode(captured, '123456');
      expect(verified.user.id, principal);
      expect(verified.authSubject, authUser);
      expect(calls.first.url.path, '/functions/v1/collect-api/v1/auth/otp');
      expect(
        (jsonDecode(calls.first.body) as Map)['should_create_user'],
        isFalse,
      );
      expect(
        calls.every((request) => request.headers['apikey'] == publishable),
        isTrue,
      );
    },
  );
}
