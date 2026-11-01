import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _subject = '11111111-1111-4111-8111-111111111111';
const _principal = '22222222-2222-4222-8222-222222222222';
const _session = '33333333-3333-4333-8333-333333333333';
const _challenge = '44444444-4444-4444-8444-444444444444';
const _profile = <String, String>{
  'admin_origin': 'https://admin.collect.example',
  'environment': 'production',
  'format': 'collect.deployment.v1',
  'google_callback_origin': 'https://admin.collect.example',
  'id': 'collect-selfhost',
  'member_api_origin': 'https://api.collect.example',
  'mode': 'self_hosted',
  'public_origin': 'https://collect.example',
  'supabase_origin': 'https://supabase.collect.example',
};

AppEnv _environment({
  String? encoded,
  String? digest,
  String? issuer,
  String? api,
}) {
  final raw = encoded ?? jsonEncode(_profile);
  return AppEnv(
    environmentName: 'production',
    apiUrl: _profile['member_api_origin']!,
    publicUrl: _profile['public_origin']!,
    adminAppUrl: _profile['admin_origin']!,
    enableSmsReader: false,
    enableAndroidSmsAccess: false,
    enableAdminPanel: false,
    enableAdminDevTools: false,
    authCaptchaEnabled: false,
    authCaptchaProvider: 'turnstile',
    authCaptchaSiteKey: '',
    supabaseUrl: _profile['supabase_origin']!,
    supabaseApiUrl: api ?? _profile['member_api_origin']!,
    supabaseAdminApiUrl: _profile['admin_origin']!,
    supabasePublishableKey: 'sb_publishable_synthetic_key_only',
    deploymentProfile: raw,
    deploymentProfileSha256:
        digest ?? sha256.convert(utf8.encode(raw)).toString(),
    supabaseAuthIssuer: issuer ?? '${_profile['supabase_origin']}/auth/v1',
    anonymousAuthEnabled: true,
  );
}

Map<String, dynamic> _credentials({
  bool guest = true,
  String subject = _subject,
  int? expiry,
}) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return {
    'access_token':
        '${part({'alg': 'ES256'})}.${part({'sub': subject, 'session_id': _session, 'iss': '${_profile['supabase_origin']}/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'is_anonymous': guest, 'exp': exp})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'user': {
      'id': guest ? subject : _principal,
      'auth_user_id': subject,
      'is_anonymous': guest,
      'aud': 'authenticated',
    },
  };
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
CollectCloudflareClient _client(
  Future<http.Response> Function(http.Request) handler, {
  CollectAuthSessionStorage? storage,
  bool guests = true,
}) {
  final config = CollectSupabaseConfiguration.fromEnvironment(_environment());
  return CollectCloudflareClient(
    config.api.origin,
    supabaseConfiguration: config,
    httpClient: MockClient(handler),
    sessionStorage: storage,
    allowAnonymousSignIn: guests,
    captchaProvider: () async => 'synthetic-captcha',
  );
}

void main() {
  test(
    'canonical self-host profile pins public issuer, callback and every application origin',
    () {
      final config = CollectSupabaseConfiguration.fromEnvironment(
        _environment(),
      );
      expect(config.authIssuer, 'https://supabase.collect.example/auth/v1');
      expect(config.googleCallbackOrigin, 'https://admin.collect.example');
      expect(
        config
            .adminRequest(
              'auth/session',
              browserOrigin: Uri.parse(_profile['admin_origin']!),
            )
            .host,
        'admin.collect.example',
      );
      for (final env in [
        _environment(digest: '0' * 64),
        _environment(issuer: 'http://api-gw:8000/auth/v1'),
        _environment(api: 'https://other.collect.example'),
        _environment(encoded: ' ${jsonEncode(_profile)}'),
        _environment(
          encoded: jsonEncode({
            ..._profile,
            'supabase_origin': 'https://127.1',
          }),
        ),
      ]) {
        expect(
          () => CollectSupabaseConfiguration.fromEnvironment(env),
          throwsArgumentError,
        );
      }
      expect(
        () => config.adminRequest(
          'auth/session',
          browserOrigin: Uri.parse('https://evil.collect.example'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'self-host Google authorization is pinned to the configured public project and callback',
    () {
      final config = CollectSupabaseConfiguration.fromEnvironment(
        _environment(),
      );
      final callback = Uri.parse(
        '${config.googleCallbackOrigin}/functions/v1/collect-api/v1/auth/google/callback',
      ).replace(queryParameters: {'state': 'a' * 43});
      final valid =
          Uri.parse(
            '${config.googleAuthorizationOrigin}/auth/v1/authorize',
          ).replace(
            queryParameters: {
              'provider': 'google',
              'redirect_to': callback.toString(),
              'code_challenge': 'b' * 43,
              'code_challenge_method': 's256',
            },
          );
      bool allowed(Uri candidate) => collectGoogleAuthorizationUrlAllowed(
        candidate,
        usesSupabase: true,
        supabaseCallbackOrigin: config.googleCallbackOrigin!,
        supabaseConfiguration: config,
      );
      expect(allowed(valid), isTrue);
      expect(
        allowed(valid.replace(host: 'rrlduytparvsjfmegalh.supabase.co')),
        isFalse,
      );
      expect(
        allowed(
          valid.replace(
            queryParameters: {
              ...valid.queryParameters,
              'redirect_to': callback
                  .replace(host: 'api.collect.example')
                  .toString(),
            },
          ),
        ),
        isFalse,
      );
      expect(allowed(Uri.parse('$valid&provider=google')), isFalse);
    },
  );

  test(
    'SMS and WhatsApp are independent explicit channels with no fallback',
    () async {
      final sent = <Map<String, dynamic>>[];
      final client = _client((request) async {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json({
          'challenge_id': _challenge,
          'retry_after': 60,
          'delivery_status': 'accepted',
        });
      });
      addTearDown(client.dispose);
      final gateway = CollectAuthOtpGateway(client, smsSignInEnabled: true);
      expect(gateway.whatsAppSignInAvailable, isFalse);
      expect(gateway.smsSignInAvailable, isTrue);
      await gateway.requestSmsOtpReceipt(phone: '+250788123456');
      expect(sent.single['channel'], 'sms');
      await expectLater(
        gateway.sendWhatsAppOtp(phone: '+250788123456'),
        throwsA(isA<CollectAuthException>()),
      );
      expect(sent.length, 1);
      await expectLater(
        client.auth.verifyOTP(
          phone: '+250788123456',
          token: '123456',
          type: CollectOtpType.sms,
          channel: CollectOtpChannel.whatsapp,
        ),
        throwsA(isA<CollectAuthException>()),
      );
      expect(sent.length, 1);
    },
  );

  test(
    'guest feature is off by default and never becomes business ownership',
    () async {
      final calls = <String>[];
      final disabled = _client((request) async {
        calls.add(request.url.path);
        return _json(_credentials());
      }, guests: false);
      addTearDown(disabled.dispose);
      await expectLater(
        disabled.auth.signInAnonymously(),
        throwsA(isA<CollectAuthException>()),
      );
      expect(calls, isEmpty);
      final client = _client((request) async {
        calls.add(request.url.path);
        return _json(_credentials());
      });
      addTearDown(client.dispose);
      await client.auth.signInAnonymously();
      expect(client.auth.currentUser, isNull);
      expect(client.auth.currentGuest?.id, _subject);
      await expectLater(
        client.rpc('create_collection'),
        throwsA(isA<CollectAuthException>()),
      );
      expect(calls.length, 1);
      await expectLater(
        client.auth.signInAnonymously(),
        throwsA(isA<CollectAuthException>()),
      );
      expect(calls.length, 1);
    },
  );

  test(
    'guest upgrade preserves Auth UUID and creates member ownership only after verification',
    () async {
      final routes = <String>[];
      final client = _client((request) async {
        routes.add(request.url.path);
        if (request.url.path.endsWith('/anonymous')) {
          return _json(_credentials());
        }
        expect(request.headers['Authorization'], startsWith('Bearer '));
        if (request.url.path.endsWith('/upgrade/otp')) {
          return _json({
            'challenge_id': _challenge,
            'retry_after': 60,
            'delivery_status': 'accepted',
          });
        }
        return _json(_credentials(guest: false));
      });
      addTearDown(client.dispose);
      await client.auth.signInAnonymously();
      await client.auth.signInWithOtp(email: 'member@example.test');
      expect(client.auth.currentUser, isNull);
      await client.auth.verifyOTP(
        email: 'member@example.test',
        token: '123456',
        type: CollectOtpType.email,
      );
      expect(client.auth.currentUser?.id, _principal);
      expect(client.auth.currentSession?.authSubject, _subject);
      expect(client.auth.pendingGuestUpgrade, isNull);
      expect(routes.last, endsWith('/upgrade/verify'));
    },
  );

  test(
    'lost upgrade reply survives restart and cancellation and reconciles without code replay',
    () async {
      final storage = CollectMemorySessionStorage();
      final routes = <String>[];
      Future<http.Response> handler(http.Request request) async {
        routes.add(request.url.path);
        if (request.url.path.endsWith('/anonymous')) {
          return _json(_credentials());
        }
        if (request.url.path.endsWith('/upgrade/otp')) {
          return _json({
            'challenge_id': _challenge,
            'retry_after': 60,
            'delivery_status': 'accepted',
          });
        }
        if (request.url.path.endsWith('/upgrade/verify')) {
          throw http.ClientException('lost acknowledgement');
        }
        if (request.url.path.endsWith('/upgrade/reconcile')) {
          return _json(_credentials(guest: false));
        }
        throw StateError('Unexpected refresh/replay');
      }

      final client = _client(handler, storage: storage);
      await client.auth.signInAnonymously();
      await client.auth.signInWithOtp(email: 'member@example.test');
      await expectLater(
        client.auth.verifyOTP(
          email: 'member@example.test',
          token: '123456',
          type: CollectOtpType.email,
        ),
        throwsA(isA<CollectAuthException>()),
      );
      expect(client.auth.pendingGuestUpgrade?.unconfirmed, isTrue);
      client.auth.cancelOtpSignIn();
      await expectLater(
        client.auth.refreshSession(),
        throwsA(isA<CollectAuthException>()),
      );
      await client.dispose();
      final restored = _client(handler, storage: storage);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.auth.pendingGuestUpgrade?.unconfirmed, isTrue);
      await restored.auth.reconcileGuestUpgrade();
      expect(restored.auth.currentUser?.id, _principal);
      expect(routes.where((r) => r.endsWith('/upgrade/verify')).length, 1);
      expect(routes.where((r) => r.endsWith('/upgrade/reconcile')).length, 1);
    },
  );

  test(
    'late verification cannot replace a changed account or move pending work',
    () async {
      final reply = Completer<http.Response>();
      final called = Completer<void>();
      final client = _client((request) async {
        if (request.url.path.endsWith('/anonymous')) {
          return _json(_credentials());
        }
        if (request.url.path.endsWith('/upgrade/otp')) {
          return _json({
            'challenge_id': _challenge,
            'retry_after': 60,
            'delivery_status': 'accepted',
          });
        }
        called.complete();
        return reply.future;
      });
      addTearDown(client.dispose);
      await client.auth.signInAnonymously();
      await client.auth.signInWithOtp(email: 'member@example.test');
      final verify = client.auth.verifyOTP(
        email: 'member@example.test',
        token: '123456',
        type: CollectOtpType.email,
      );
      final rejected = expectLater(
        verify,
        throwsA(isA<CollectAuthException>()),
      );
      await called.future;
      await client.auth.recoverSession(
        jsonEncode(
          _credentials(
            guest: false,
            subject: '55555555-5555-4555-8555-555555555555',
          ),
        ),
      );
      reply.complete(_json(_credentials(guest: false)));
      await rejected;
      expect(
        client.auth.currentSession?.authSubject,
        '55555555-5555-4555-8555-555555555555',
      );
    },
  );

  test(
    'expired guest recovery keeps renewed credentials only in the recovery journal',
    () async {
      final storage = CollectMemorySessionStorage();
      var reconciles = 0;
      final recoveryReply = Completer<http.Response>();
      final recoveryCalled = Completer<void>();
      Future<http.Response> handler(http.Request request) async {
        if (request.url.path.endsWith('/anonymous')) {
          return _json(_credentials());
        }
        if (request.url.path.endsWith('/upgrade/otp')) {
          return _json({
            'challenge_id': _challenge,
            'retry_after': 60,
            'delivery_status': 'accepted',
          });
        }
        if (request.url.path.endsWith('/upgrade/verify')) {
          throw http.ClientException('lost acknowledgement');
        }
        if (request.url.path.endsWith('/upgrade/reconcile')) {
          reconciles++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('code'), isFalse);
          if (reconciles == 1) {
            expect(body['refresh_token'], 'synthetic-refresh');
            recoveryCalled.complete();
            return recoveryReply.future;
          }
          expect(body['refresh_token'], 'synthetic-renewed-recovery');
          return _json(_credentials(guest: false));
        }
        throw StateError('Unexpected ordinary refresh or code replay');
      }

      final initial = _client(handler, storage: storage);
      await initial.auth.signInAnonymously();
      await initial.auth.signInWithOtp(email: 'member@example.test');
      await expectLater(
        initial.auth.verifyOTP(
          email: 'member@example.test',
          token: '123456',
          type: CollectOtpType.email,
        ),
        throwsA(isA<CollectAuthException>()),
      );
      await initial.dispose();
      final persisted =
          jsonDecode((await storage.read())!) as Map<String, dynamic>;
      persisted['access_token'] = _credentials(expiry: 1)['access_token'];
      await storage.write(jsonEncode(persisted));
      final restored = _client(handler, storage: storage);
      await restored.initialize();
      expect(restored.auth.currentSession!.isExpired, isTrue);
      final first = expectLater(
        restored.auth.reconcileGuestUpgrade(),
        throwsA(isA<CollectAuthException>()),
      );
      final concurrent = expectLater(
        restored.auth.reconcileGuestUpgrade(),
        throwsA(isA<CollectAuthException>()),
      );
      await recoveryCalled.future;
      recoveryReply.complete(
        _json({
          'upgrade_status': 'unconfirmed',
          'challenge_id': _challenge,
          'auth_user_id': _subject,
          'initiating_session_id': _session,
          'recovery_refresh_token': 'synthetic-renewed-recovery',
        }),
      );
      await Future.wait([first, concurrent]);
      expect(reconciles, 1);
      expect(restored.auth.currentUser, isNull);
      expect(restored.auth.currentGuest?.id, _subject);
      expect(restored.auth.pendingGuestUpgrade?.unconfirmed, isTrue);
      await restored.dispose();
      final again = _client(handler, storage: storage, guests: false);
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.auth.anonymousSignInAvailable, isFalse);
      expect(again.auth.pendingGuestUpgrade?.unconfirmed, isTrue);
      await again.auth.reconcileGuestUpgrade();
      expect(reconciles, 2);
      expect(again.auth.currentUser?.id, _principal);
      expect(again.auth.pendingGuestUpgrade, isNull);
    },
  );
}
