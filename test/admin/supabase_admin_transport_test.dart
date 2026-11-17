import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cloud Admin CAPTCHA stays on its approved cookie origin', () async {
    const profile = <String, String>{
      'admin_origin': 'https://platform-admin.collect.ikanisa.com',
      'environment': 'production',
      'format': 'collect.deployment.v1',
      'google_callback_origin': 'https://platform-admin.collect.ikanisa.com',
      'id': 'collect-production',
      'member_api_origin': 'https://api.collect.ikanisa.com',
      'mode': 'managed',
      'public_origin': 'https://collect.ikanisa.com',
      'supabase_origin': 'https://rrlduytparvsjfmegalh.supabase.co',
    };
    final encoded = jsonEncode(profile);
    final environment = AppEnv(
      environmentName: 'production',
      apiUrl: profile['member_api_origin']!,
      publicUrl: profile['public_origin']!,
      adminAppUrl: profile['admin_origin']!,
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: true,
      enableAdminDevTools: false,
      authCaptchaEnabled: true,
      authCaptchaProvider: 'turnstile',
      authCaptchaSiteKey: 'synthetic-public-site-key',
      supabaseUrl: profile['supabase_origin']!,
      supabaseApiUrl: profile['member_api_origin']!,
      supabaseAdminApiUrl: profile['admin_origin']!,
      supabasePublishableKey: fixtures.publishable,
      deploymentProfile: encoded,
      deploymentProfileSha256: sha256.convert(utf8.encode(encoded)).toString(),
      supabaseAuthIssuer: '${profile['supabase_origin']}/auth/v1',
    );
    const channel = MethodChannel('collect/turnstile');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var challenges = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'acquire') return null;
      challenges++;
      final args = call.arguments as Map;
      expect(args['backend_origin'], profile['admin_origin']);
      expect(
        args['backend_path'],
        '/functions/v1/collect-api/v1/security/challenge',
      );
      return jsonEncode({
        'type': 'collect.turnstile.v1',
        'attempt_id': args['attempt_id'],
        'token': 'synthetic-candidate',
      });
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <http.Request>[];
    final controller = CloudflareAdminSession(
      MockClient((request) async {
        calls.add(request);
        return http.Response('{}', 200);
      }),
      origin: Uri.parse(profile['admin_origin']!),
      environment: environment,
    );
    addTearDown(controller.dispose);
    await controller.request(
      'auth/otp',
      body: const {'email': 'synthetic@example.invalid'},
    );
    expect(challenges, 1);
    expect(calls.single.url.origin, profile['admin_origin']);
    expect(calls.single.url.path, '/functions/v1/admin-api/api/admin/auth/otp');
    expect(
      (jsonDecode(calls.single.body) as Map)['captcha_token'],
      'synthetic-candidate',
    );
    expect(
      () => CloudflareAdminSession(
        MockClient(
          (_) async => throw StateError('Foreign origin must not dispatch'),
        ),
        origin: Uri.parse(profile['member_api_origin']!),
        environment: environment,
      ),
      throwsArgumentError,
    );
  });
  test(
    'Supabase Admin challenges send, resend, password and recovery, not code verify',
    () async {
      const channel = MethodChannel('collect/turnstile');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var challenges = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'acquire') return null;
        challenges++;
        final args = call.arguments as Map;
        expect(args['backend_origin'], 'https://backend.collect.ikanisa.com');
        return jsonEncode({
          'type': 'collect.turnstile.v1',
          'attempt_id': args['attempt_id'],
          'token': 'candidate-$challenges',
        });
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final calls = <http.Request>[];
      final controller = CloudflareAdminSession(
        MockClient((request) async {
          calls.add(request);
          return http.Response('{}', 200);
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(
          captcha: true,
          api: 'https://backend.collect.ikanisa.com',
        ),
      );
      addTearDown(controller.dispose);
      await controller.request(
        'auth/otp',
        body: const {'email': 'synthetic@example.invalid'},
      );
      await controller.request(
        'auth/otp',
        body: const {'email': 'synthetic@example.invalid'},
      );
      await controller.request(
        'auth/login',
        body: const {'password': 'fixture'},
      );
      await controller.request(
        'auth/forgot-password',
        body: const {'email': 'synthetic@example.invalid'},
      );
      await controller.request('auth/verify', body: const {'code': '123456'});
      expect(challenges, 4);
      expect(calls, hasLength(5));
      for (var index = 0; index < 4; index++) {
        expect(
          (jsonDecode(calls[index].body) as Map)['captcha_token'],
          'candidate-${index + 1}',
        );
      }
      expect(
        (jsonDecode(calls.last.body) as Map).containsKey('captcha_token'),
        isFalse,
      );
    },
  );
  test(
    'signed-out Supabase session accepts absent CSRF without inventing admission',
    () async {
      final controller = CloudflareAdminSession(
        MockClient(
          (_) async =>
              http.Response(jsonEncode({'user': null, 'csrfToken': null}), 200),
        ),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.user, isNull);
      expect(controller.state.hasError, isFalse);
    },
  );
  test(
    'Supabase Admin keeps cookies in browser custody and CSRF only in memory',
    () async {
      final calls = <http.Request>[];
      final controller = CloudflareAdminSession(
        MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode({'csrfToken': 'a' * 64, 'ok': true}),
            200,
          );
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
      );
      addTearDown(controller.dispose);
      await controller.request('auth/session');
      await controller.request('auth/logout', body: const {});
      expect(
        calls.last.url.toString(),
        'https://backend.collect.ikanisa.com/functions/v1/admin-api/api/admin/auth/logout',
      );
      expect(calls.last.headers['X-Collect-CSRF'], 'a' * 64);
      expect(calls.last.headers['X-Collect-Requested-With'], 'collect-admin');
      expect(calls.last.headers['apikey'], fixtures.publishable);
      expect(calls.last.headers.containsKey('authorization'), isFalse);
      expect(calls.last.headers.containsKey('cookie'), isFalse);
      controller.clear();
      await controller.request(
        'auth/otp',
        body: const {'email': 'synthetic@example.invalid'},
      );
      expect(calls.last.headers.containsKey('X-Collect-CSRF'), isFalse);
    },
  );

  test(
    'Supabase Admin refuses a cross-site cookie deployment before requests',
    () {
      expect(
        () => CloudflareAdminSession(
          MockClient((_) async => http.Response('{}', 500)),
          origin: Uri.parse('https://admin.collect.ikanisa.com'),
          environment: fixtures.environment(admin: fixtures.project),
        ),
        throwsArgumentError,
      );
    },
  );
}
