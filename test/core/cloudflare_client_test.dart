import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';

const _actor = '11111111-1111-4111-8111-111111111111';
const _session = '22222222-2222-4222-8222-222222222222';
const _otherActor = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> _credentials({
  String actor = _actor,
  String session = _session,
  String refresh = 'opaque-refresh',
  int? expiresAt,
}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      expiresAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
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

CollectSupabaseConfiguration _guestConfiguration() {
  const env = AppEnv(
    apiUrl: 'https://api.example.com',
    publicUrl: 'https://collect.example.com',
    adminAppUrl: 'https://admin.example.com',
    enableSmsReader: false,
    enableAndroidSmsAccess: false,
    enableAdminPanel: false,
    enableAdminDevTools: false,
    authCaptchaEnabled: false,
    authCaptchaProvider: '',
    authCaptchaSiteKey: '',
    supabaseUrl: 'https://project.example.com',
    supabaseApiUrl: 'https://api.example.com',
    supabasePublishableKey: 'sb_publishable_synthetic_key_only',
  );
  return CollectSupabaseConfiguration.fromEnvironment(env);
}

Map<String, dynamic> _guestCredentials(
  CollectSupabaseConfiguration config, {
  required bool unconfirmed,
  int expiresAt = 1,
  String session = _session,
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return _credentials(expiresAt: expiresAt, session: session)
    ..['access_token'] =
        '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'session_id': session, 'iss': config.authIssuer, 'aud': 'authenticated', 'role': 'authenticated', 'is_anonymous': true, 'exp': expiresAt})}.synthetic'
    ..['user'] = {
      'id': _actor,
      'auth_user_id': _actor,
      'is_anonymous': true,
      'aud': 'authenticated',
    }
    ..['guest_upgrade'] = {
      'challenge_id': '44444444-4444-4444-8444-444444444444',
      'auth_subject': _actor,
      'session_id': session,
      'phone': '+250788123456',
      'email': null,
      'channel': 'sms',
      'unconfirmed': unconfirmed,
    };
}

Map<String, dynamic> _memberCredentials(CollectSupabaseConfiguration config) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return _credentials(actor: _otherActor, expiresAt: expiry)
    ..['access_token'] =
        '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'session_id': _session, 'iss': config.authIssuer, 'aud': 'authenticated', 'role': 'authenticated', 'is_anonymous': false, 'exp': expiry})}.synthetic'
    ..['user'] = {
      'id': _otherActor,
      'auth_user_id': _actor,
      'is_anonymous': false,
      'aud': 'authenticated',
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

  for (final transition in [
    'unchanged',
    'A to B to A',
    'sign-out',
    'same session',
  ]) {
    test(
      'OTP verification checks $transition during protected storage',
      () async {
        final storage = _BarrierStorage();
        final original = _credentials();
        var verificationRequests = 0;
        final client = CollectCloudflareClient(
          'https://api.example.com',
          sessionStorage: storage,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/otp')) {
              return _json({'challenge_id': 'challenge'});
            }
            expect(request.url.path, '/v1/auth/verify');
            verificationRequests++;
            return _json(original);
          }),
        );
        final events = <String?>[];
        final subscription = client.auth.onAuthStateChange.listen(
          (event) => events.add(event.session?.user.id),
        );
        addTearDown(() async {
          if (!storage.release.isCompleted) storage.release.complete();
          await subscription.cancel();
          await client.dispose();
        });

        await client.auth.signInWithOtp(phone: '+250788123456');
        final verifying = client.auth.verifyOTP(
          phone: '+250788123456',
          token: '123456',
          type: CollectOtpType.sms,
        );
        final checked = transition == 'unchanged'
            ? expectLater(verifying, completion(isA<CollectAuthResponse>()))
            : expectLater(
                verifying,
                throwsA(
                  isA<CollectAuthException>().having(
                    (error) => error.code,
                    'reason',
                    'session_changed',
                  ),
                ),
              );
        await storage.started.future;
        expect(client.auth.currentUser?.id, _actor);
        expect(events, [_actor]);

        final adoptions = <Future<CollectAuthResponse>>[];
        Future<void>? clearing;
        if (transition == 'A to B to A') {
          adoptions.add(
            client.auth.recoverSession(
              jsonEncode(
                _credentials(
                  actor: _otherActor,
                  session: '44444444-4444-4444-8444-444444444444',
                ),
              ),
            ),
          );
          expect(client.auth.currentUser?.id, _otherActor);
          adoptions.add(client.auth.recoverSession(jsonEncode(original)));
          expect(
            client.auth.currentSession?.accessToken,
            original['access_token'],
          );
          expect(events, [_actor, _otherActor, _actor]);
        } else if (transition == 'sign-out') {
          clearing = client.auth.clearLocalSession();
          expect(client.auth.currentSession, isNull);
          expect(events, [_actor, null]);
        } else if (transition == 'same session') {
          adoptions.add(client.auth.recoverSession(jsonEncode(original)));
          expect(
            client.auth.currentSession?.accessToken,
            original['access_token'],
          );
          expect(events, [_actor, _actor]);
        }

        storage.release.complete();
        await checked;
        await Future.wait(adoptions);
        if (clearing != null) await clearing;
        expect(verificationRequests, 1);
        expect(
          client.auth.currentUser?.id,
          transition == 'sign-out' ? null : _actor,
        );
        if (transition == 'unchanged') {
          expect(
            (await verifying).session?.accessToken,
            original['access_token'],
          );
        }
      },
    );
  }

  for (final stale in ['valid', 'invalid', 'read failure', 'sign-out']) {
    test('stale initialization $stale cannot replace a newer session', () async {
      final storage = _InitializationStorage();
      final replacement = _credentials(actor: _otherActor);
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected network'),
        ),
      );
      final events = <CollectAuthEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await subscription.cancel();
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      if (stale == 'sign-out') {
        await client.auth.clearLocalSession();
      } else {
        await client.auth.recoverSession(jsonEncode(replacement));
      }
      // The original read is still held; a newer lifecycle must not wait on it.
      await client.initialize().timeout(const Duration(seconds: 1));
      expect(storage.reads, 1);
      if (stale == 'read failure') {
        storage.readReply.completeError(StateError('Synthetic read failure'));
      } else {
        storage.readReply.complete(
          stale == 'invalid' ? '{invalid' : jsonEncode(_credentials()),
        );
      }
      await initializing;
      expect(
        client.auth.currentUser?.id,
        stale == 'sign-out' ? null : _otherActor,
      );
      expect(events, [
        stale == 'sign-out'
            ? CollectAuthEvent.signedOut
            : CollectAuthEvent.signedIn,
      ]);
      expect(storage.clears, stale == 'sign-out' ? 1 : 0);
      if (stale != 'sign-out') {
        expect(
          jsonDecode(storage.value!)['access_token'],
          replacement['access_token'],
        );
      }
    });
  }

  for (final clearFails in [false, true]) {
    test(
      'stale invalid-store clear cannot erase a later write (failure=$clearFails)',
      () async {
        final storage = _InitializationStorage()
          ..clearRelease = Completer<void>()
          ..clearFails = clearFails;
        final replacement = _credentials(actor: _otherActor);
        final client = CollectCloudflareClient(
          'https://api.example.com',
          sessionStorage: storage,
          httpClient: MockClient(
            (_) async => throw StateError('Unexpected network'),
          ),
        );
        addTearDown(() async {
          if (!storage.readReply.isCompleted) storage.readReply.complete(null);
          if (!storage.clearRelease!.isCompleted)
            storage.clearRelease!.complete();
          await client.dispose();
        });
        final initializing = client.initialize();
        await storage.readStarted.future;
        storage.readReply.complete('{invalid');
        await storage.clearStarted.future;
        final adoption = client.auth.recoverSession(jsonEncode(replacement));
        expect(client.auth.currentUser?.id, _otherActor);
        expect(storage.writes, 0);
        storage.clearRelease!.complete();
        await initializing;
        await adoption;
        expect(storage.operations, [
          'clear:start',
          clearFails ? 'clear:failed' : 'clear:end',
          'write',
        ]);
        expect(
          jsonDecode(storage.value!)['access_token'],
          replacement['access_token'],
        );
        expect(client.auth.currentUser?.id, _otherActor);
      },
    );
  }

  test(
    'overlapping initialization shares one restore and one initial event',
    () async {
      final storage = _InitializationStorage();
      final original = _credentials();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected network'),
        ),
      );
      final events = <CollectAuthEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await subscription.cancel();
        await client.dispose();
      });
      final first = client.initialize();
      final second = client.initialize();
      expect(identical(first, second), isTrue);
      await storage.readStarted.future;
      expect(storage.reads, 1);
      storage.readReply.complete(jsonEncode(original));
      await Future.wait([first, second]);
      expect(events, [CollectAuthEvent.initialSession]);
      expect(client.auth.currentSession?.accessToken, original['access_token']);
      await client.initialize();
      expect(storage.reads, 1);
    },
  );

  test(
    'invalid startup storage is cleared when initialization still owns it',
    () async {
      final storage = _InitializationStorage()
        ..value = 'synthetic invalid value';
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected network'),
        ),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      storage.readReply.complete('{invalid');
      await initializing;
      expect(storage.clears, 1);
      expect(storage.value, isNull);
      expect(client.auth.currentSession, isNull);
    },
  );

  for (final allowGuests in [false, true]) {
    test(
      'expired unconfirmed guest restores without refresh (new guests=$allowGuests)',
      () async {
        final config = _guestConfiguration();
        final guest = _guestCredentials(config, unconfirmed: true);
        final storage = _InitializationStorage();
        var requests = 0;
        final client = CollectCloudflareClient(
          config.api.origin,
          supabaseConfiguration: config,
          allowAnonymousSignIn: allowGuests,
          sessionStorage: storage,
          httpClient: MockClient((_) async {
            requests++;
            throw StateError('Unexpected network');
          }),
        );
        final events = <CollectAuthEvent>[];
        final subscription = client.auth.onAuthStateChange.listen(
          (event) => events.add(event.event),
        );
        addTearDown(() async {
          if (!storage.readReply.isCompleted) storage.readReply.complete(null);
          await subscription.cancel();
          await client.dispose();
        });
        final initializing = client.initialize();
        await storage.readStarted.future;
        storage.readReply.complete(jsonEncode(guest));
        await initializing;
        expect(client.auth.currentGuest?.id, _actor);
        expect(client.auth.currentSession?.isExpired, isTrue);
        expect(client.auth.pendingGuestUpgrade?.unconfirmed, isTrue);
        expect(client.auth.pendingGuestUpgrade?.channel, CollectOtpChannel.sms);
        expect(events, [CollectAuthEvent.initialSession]);
        expect(requests, 0);
        expect(storage.clears, 0);
      },
    );
  }

  for (final outcome in [
    'success enabled',
    'success disabled',
    'cancel OTP',
    'cancel Google',
    'foreign session',
    'failure',
    'sign-out',
  ]) {
    test('retained guest initialization fences OTP ($outcome)', () async {
      final config = _guestConfiguration();
      final storage = _InitializationStorage();
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final routes = <String>[];
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final refreshed = _guestCredentials(
        config,
        unconfirmed: false,
        expiresAt: expiry,
      );
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        allowAnonymousSignIn: outcome != 'success disabled',
        sessionStorage: storage,
        httpClient: MockClient((request) async {
          final path = request.url.path;
          routes.add(path);
          if (path.endsWith('/refresh')) {
            entered.complete();
            return reply.future;
          }
          if (path.endsWith('/upgrade/otp') || path.endsWith('/otp')) {
            return _json({
              'challenge_id': '44444444-4444-4444-8444-444444444444',
              'retry_after': 60,
              'delivery_status': 'accepted',
            });
          }
          expect(path.endsWith('/verify'), isTrue);
          return _json(_memberCredentials(config));
        }),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        if (!reply.isCompleted) reply.complete(_json({}, 401));
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      storage.readReply.complete(
        jsonEncode(_guestCredentials(config, unconfirmed: false)),
      );
      await entered.future;
      expect(client.auth.currentSession, isNull);
      final pendingError = throwsA(
        isA<CollectAuthException>().having(
          (error) => error.code,
          'reason',
          'guest_initialization_pending',
        ),
      );
      await expectLater(
        client.auth.signInWithOtp(
          phone: '+250788123456',
          channel: CollectOtpChannel.sms,
        ),
        pendingError,
      );
      await expectLater(
        client.auth.signInWithOtp(email: 'member@example.com'),
        pendingError,
      );
      if (outcome == 'cancel OTP') client.auth.cancelOtpSignIn();
      if (outcome == 'cancel Google') client.auth.cancelGoogleSignIn();
      if (outcome.startsWith('cancel ')) {
        await expectLater(
          client.auth.signInWithOtp(
            phone: '+250788123456',
            channel: CollectOtpChannel.sms,
          ),
          pendingError,
        );
      }
      if (outcome == 'success enabled') {
        await expectLater(client.auth.signInAnonymously(), pendingError);
        var authorizationCalls = 0;
        await expectLater(
          client.auth.signInWithGoogle(
            authorize: (_, _, _) async {
              authorizationCalls++;
              return {};
            },
          ),
          pendingError,
        );
        expect(authorizationCalls, 0);
      }
      expect(routes.where((path) => path.endsWith('/otp')), isEmpty);

      if (outcome == 'sign-out') {
        await client.auth.clearLocalSession();
        await client.auth.signInWithOtp(
          phone: '+250788123456',
          channel: CollectOtpChannel.sms,
        );
      }
      reply.complete(
        outcome == 'failure'
            ? _json({}, 401)
            : outcome == 'foreign session'
            ? _json(
                _guestCredentials(
                  config,
                  unconfirmed: false,
                  expiresAt: expiry,
                  session: '55555555-5555-4555-8555-555555555555',
                ),
              )
            : _json(refreshed),
      );
      await initializing;
      if (outcome.startsWith('success') || outcome.startsWith('cancel ')) {
        expect(client.auth.currentGuest?.id, _actor);
        expect(client.auth.pendingGuestUpgrade?.unconfirmed, isFalse);
        await client.auth.signInWithOtp(
          phone: '+250788123456',
          channel: CollectOtpChannel.sms,
        );
        expect(
          routes.where((path) => path.endsWith('/upgrade/otp')),
          hasLength(1),
        );
        expect(routes.where((path) => path.endsWith('/auth/otp')), isEmpty);
        if (outcome == 'success disabled') {
          await expectLater(
            client.auth.signInAnonymously(),
            throwsA(
              isA<CollectAuthException>().having(
                (error) => error.code,
                'reason',
                'anonymous_unavailable',
              ),
            ),
          );
        }
      } else if (outcome == 'failure' || outcome == 'foreign session') {
        expect(client.auth.currentSession, isNull);
        expect(storage.clears, 1);
        expect(routes.where((path) => path.endsWith('/otp')), isEmpty);
      } else {
        expect(client.auth.currentSession, isNull);
        expect(
          routes.where((path) => path.endsWith('/auth/otp')),
          hasLength(1),
        );
        expect(routes.where((path) => path.endsWith('/upgrade/otp')), isEmpty);
        await client.auth.verifyOTP(
          phone: '+250788123456',
          token: '123456',
          type: CollectOtpType.sms,
          channel: CollectOtpChannel.sms,
        );
        expect(client.auth.currentUser?.id, _otherActor);
      }
    });
  }

  for (final scenario in [
    (duringWrite: false, clearFails: false, onSignOut: false),
    (duringWrite: false, clearFails: true, onSignOut: false),
    (duringWrite: true, clearFails: false, onSignOut: false),
    (duringWrite: true, clearFails: true, onSignOut: false),
    (duringWrite: false, clearFails: false, onSignOut: true),
    (duringWrite: false, clearFails: true, onSignOut: true),
  ]) {
    test(
      'guest cancellation waits for failed-write cleanup $scenario',
      () async {
        final clearFails = scenario.clearFails;
        final config = _guestConfiguration();
        final storage = _InitializationStorage()
          ..writeFails = true
          ..clearFails = clearFails
          ..clearRelease = Completer<void>()
          ..writeRelease = scenario.duringWrite ? Completer<void>() : null;
        final entered = Completer<void>();
        final reply = Completer<http.Response>();
        final client = CollectCloudflareClient(
          config.api.origin,
          supabaseConfiguration: config,
          allowAnonymousSignIn: true,
          sessionStorage: storage,
          httpClient: MockClient((request) async {
            expect(request.url.path.endsWith('/refresh'), isTrue);
            entered.complete();
            return reply.future;
          }),
        );
        final subscription = client.auth.onAuthStateChange.listen((event) {
          if (scenario.onSignOut && event.event == CollectAuthEvent.signedOut) {
            client.auth.cancelOtpSignIn();
            client.auth.cancelGoogleSignIn();
          }
        });
        addTearDown(() async {
          if (!storage.readReply.isCompleted) storage.readReply.complete(null);
          if (!reply.isCompleted) reply.complete(_json({}, 401));
          if (storage.writeRelease case final release?) {
            if (!release.isCompleted) release.complete();
          }
          if (!storage.clearRelease!.isCompleted)
            storage.clearRelease!.complete();
          await subscription.cancel();
          await client.dispose();
        });
        final initializing = client.initialize();
        final checked = clearFails
            ? expectLater(initializing, throwsStateError)
            : expectLater(initializing, completes);
        var settled = false;
        final observed = initializing.then<void>(
          (_) {
            settled = true;
          },
          onError: (Object _, StackTrace _) {
            settled = true;
          },
        );
        await storage.readStarted.future;
        storage.readReply.complete(
          jsonEncode(_guestCredentials(config, unconfirmed: false)),
        );
        await entered.future;
        if (!scenario.duringWrite) {
          client.auth.cancelOtpSignIn();
          client.auth.cancelGoogleSignIn();
        }
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        reply.complete(
          _json(
            _guestCredentials(config, unconfirmed: false, expiresAt: expiry),
          ),
        );
        if (scenario.duringWrite) {
          await storage.writeStarted.future;
          client.auth.cancelOtpSignIn();
          client.auth.cancelGoogleSignIn();
          storage.writeRelease!.complete();
        }
        await storage.clearStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        storage.clearRelease!.complete();
        await checked;
        await observed;
        expect(client.auth.currentSession, isNull);
        expect(storage.clears, 1);
      },
    );
  }

  for (final clearFails in [false, true]) {
    test(
      'failed non-startup persistence orders replacement after clear (failure=$clearFails)',
      () async {
        final storage = _InitializationStorage()
          ..writeFails = true
          ..clearFails = clearFails
          ..clearRelease = Completer<void>();
        final replacement = _credentials(actor: _otherActor);
        final client = CollectCloudflareClient(
          'https://api.example.com',
          sessionStorage: storage,
          httpClient: MockClient(
            (_) async => throw StateError('Unexpected network'),
          ),
        );
        addTearDown(() async {
          if (!storage.clearRelease!.isCompleted)
            storage.clearRelease!.complete();
          await client.dispose();
        });
        final original = client.auth.recoverSession(jsonEncode(_credentials()));
        final failed = expectLater(
          original,
          throwsA(
            isA<CollectAuthException>().having(
              (error) => error.code,
              'reason',
              'protected_storage_unavailable',
            ),
          ),
        );
        await storage.clearStarted.future;
        storage.writeFails = false;
        final next = client.auth.recoverSession(jsonEncode(replacement));
        expect(client.auth.currentUser?.id, _otherActor);
        expect(storage.writes, 1);
        storage.clearRelease!.complete();
        await failed;
        await next;
        expect(storage.operations, [
          'write',
          'clear:start',
          clearFails ? 'clear:failed' : 'clear:end',
          'write',
        ]);
        expect(
          jsonDecode(storage.value!)['access_token'],
          replacement['access_token'],
        );
        expect(client.auth.currentUser?.id, _otherActor);
      },
    );
  }

  test('new OTP is not owned by an older failed-write clear', () async {
    final config = _guestConfiguration();
    final storage = _InitializationStorage()
      ..writeFails = true
      ..clearFails = true
      ..clearRelease = Completer<void>();
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    late Future<CollectOtpRequestReceipt> nextOtp;
    final client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      allowAnonymousSignIn: true,
      sessionStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          return _json(
            _guestCredentials(config, unconfirmed: false, expiresAt: expiry),
          );
        }
        if (request.url.path.endsWith('/otp')) {
          return _json({
            'challenge_id': '44444444-4444-4444-8444-444444444444',
            'retry_after': 60,
            'delivery_status': 'accepted',
          });
        }
        expect(request.url.path.endsWith('/verify'), isTrue);
        return _json(_memberCredentials(config));
      }),
    );
    final subscription = client.auth.onAuthStateChange.listen((event) {
      if (event.event == CollectAuthEvent.signedOut) {
        nextOtp = client.auth.signInWithOtp(
          phone: '+250788123456',
          channel: CollectOtpChannel.sms,
        );
        client.auth.cancelGoogleSignIn();
      }
    });
    addTearDown(() async {
      if (!storage.readReply.isCompleted) storage.readReply.complete(null);
      if (!storage.clearRelease!.isCompleted) storage.clearRelease!.complete();
      await subscription.cancel();
      await client.dispose();
    });
    final initializing = client.initialize();
    await storage.readStarted.future;
    storage.readReply.complete(
      jsonEncode(_guestCredentials(config, unconfirmed: false)),
    );
    await storage.clearStarted.future;
    await initializing.timeout(const Duration(seconds: 1));
    await nextOtp;
    storage.clearRelease!.complete();
    storage.writeFails = false;
    await client.auth.verifyOTP(
      phone: '+250788123456',
      token: '123456',
      type: CollectOtpType.sms,
      channel: CollectOtpChannel.sms,
    );
    expect(client.auth.currentUser?.id, _otherActor);
    expect(jsonDecode(storage.value!)['user']['id'], _otherActor);
  });

  test(
    'a pending OTP challenge survives an older initialization read',
    () async {
      final storage = _InitializationStorage();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (request) async => request.url.path.endsWith('/otp')
              ? _json({'challenge_id': 'challenge'})
              : _json(_credentials()),
        ),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      await client.auth.signInWithOtp(phone: '+250788123456');
      await client.initialize().timeout(const Duration(seconds: 1));
      expect(storage.reads, 1);
      storage.readReply.complete(jsonEncode(_credentials(actor: _otherActor)));
      await initializing;
      expect(client.auth.currentSession, isNull);
      await client.auth.verifyOTP(
        phone: '+250788123456',
        token: '123456',
        type: CollectOtpType.sms,
      );
      expect(client.auth.currentUser?.id, _actor);
    },
  );

  test(
    'an existing OTP challenge prevents a later initialization read',
    () async {
      final storage = _InitializationStorage();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (request) async => request.url.path.endsWith('/otp')
              ? _json({'challenge_id': 'challenge'})
              : _json(_credentials()),
        ),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await client.dispose();
      });
      await client.auth.signInWithOtp(phone: '+250788123456');
      await client.initialize();
      expect(storage.reads, 0);
      await client.auth.verifyOTP(
        phone: '+250788123456',
        token: '123456',
        type: CollectOtpType.sms,
      );
      expect(client.auth.currentUser?.id, _actor);
    },
  );

  for (final replaceSession in [false, true]) {
    test(
      'expired restore refresh failure preserves correct owner (replacement=$replaceSession)',
      () async {
        final storage = _InitializationStorage();
        final entered = Completer<void>();
        final reply = Completer<http.Response>();
        final replacement = _credentials(actor: _otherActor);
        final client = CollectCloudflareClient(
          'https://api.example.com',
          sessionStorage: storage,
          httpClient: MockClient((request) async {
            expect(request.url.path, '/v1/auth/refresh');
            entered.complete();
            return reply.future;
          }),
        );
        addTearDown(() async {
          if (!storage.readReply.isCompleted) storage.readReply.complete(null);
          if (!reply.isCompleted) reply.complete(_json({}, 401));
          await client.dispose();
        });
        final initializing = client.initialize();
        await storage.readStarted.future;
        storage.readReply.complete(jsonEncode(_credentials(expiresAt: 1)));
        await entered.future;
        if (replaceSession) {
          await client.auth.recoverSession(jsonEncode(replacement));
        }
        reply.complete(
          _json({
            'error': {'code': 'invalid_credentials'},
          }, 401),
        );
        await initializing;
        expect(
          client.auth.currentUser?.id,
          replaceSession ? _otherActor : null,
        );
        expect(storage.clears, replaceSession ? 0 : 1);
        if (replaceSession) {
          expect(
            jsonDecode(storage.value!)['access_token'],
            replacement['access_token'],
          );
        }
      },
    );
  }

  test('delayed restore refresh cannot replace a newer OTP attempt', () async {
    final storage = _InitializationStorage();
    final entered = Completer<void>();
    final reply = Completer<http.Response>();
    final client = CollectCloudflareClient(
      'https://api.example.com',
      sessionStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          entered.complete();
          return reply.future;
        }
        if (request.url.path.endsWith('/otp')) {
          return _json({'challenge_id': 'challenge'});
        }
        expect(request.url.path, '/v1/auth/verify');
        return _json(_credentials());
      }),
    );
    addTearDown(() async {
      if (!storage.readReply.isCompleted) storage.readReply.complete(null);
      if (!reply.isCompleted) reply.complete(_json({}, 401));
      await client.dispose();
    });
    final initializing = client.initialize();
    await storage.readStarted.future;
    storage.readReply.complete(jsonEncode(_credentials(expiresAt: 1)));
    await entered.future;
    await client.auth.signInWithOtp(phone: '+250788123456');
    reply.complete(_json(_credentials(refresh: 'refreshed-synthetic')));
    await initializing;
    expect(client.auth.currentSession, isNull);
    expect(client.auth.currentUser, isNull);
    expect(storage.clears, 0);
    await client.auth.verifyOTP(
      phone: '+250788123456',
      token: '123456',
      type: CollectOtpType.sms,
    );
    expect(client.auth.currentSession?.isExpired, isFalse);
    expect(client.auth.currentUser?.id, _actor);
  });

  for (final transition in ['failed OTP', 'abandoned OTP', 'sign-out']) {
    test('expired restore stays private after $transition', () async {
      final storage = _InitializationStorage();
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final original = jsonEncode(_credentials(expiresAt: 1));
      storage.value = original;
      var verifies = 0;
      final events = <CollectAuthEvent>[];
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            entered.complete();
            return reply.future;
          }
          if (request.url.path.endsWith('/otp')) {
            return transition == 'failed OTP'
                ? _json({
                    'error': {'code': 'invalid_credentials'},
                  }, 400)
                : _json({'challenge_id': 'challenge'});
          }
          verifies++;
          return _json(_credentials());
        }),
      );
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        if (!reply.isCompleted) reply.complete(_json({}, 401));
        await subscription.cancel();
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      storage.readReply.complete(original);
      await entered.future;
      expect(client.auth.currentSession, isNull);
      expect(client.auth.currentUser, isNull);
      if (transition == 'sign-out') {
        await client.auth.clearLocalSession();
      } else if (transition == 'failed OTP') {
        await expectLater(
          client.auth.signInWithOtp(phone: '+250788123456'),
          throwsA(isA<CollectAuthException>()),
        );
      } else {
        await client.auth.signInWithOtp(phone: '+250788123456');
        client.auth.cancelOtpSignIn();
      }
      reply.complete(_json(_credentials(refresh: 'refreshed-synthetic')));
      await initializing;
      expect(client.auth.currentSession, isNull);
      expect(client.auth.currentUser, isNull);
      expect(
        events,
        transition == 'sign-out' ? [CollectAuthEvent.signedOut] : isEmpty,
      );
      expect(storage.clears, transition == 'sign-out' ? 1 : 0);
      expect(storage.value, transition == 'sign-out' ? null : original);
      if (transition == 'abandoned OTP') {
        await expectLater(
          client.auth.verifyOTP(
            phone: '+250788123456',
            token: '123456',
            type: CollectOtpType.sms,
          ),
          throwsA(
            isA<CollectAuthException>().having(
              (e) => e.code,
              'reason',
              'invalid_challenge',
            ),
          ),
        );
        expect(verifies, 0);
      }
    });
  }

  test(
    'failed protected write retires a refreshed startup candidate',
    () async {
      final storage = _InitializationStorage()..writeFails = true;
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/auth/refresh');
          return _json(_credentials(refresh: 'refreshed-synthetic'));
        }),
      );
      final events = <CollectAuthEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await subscription.cancel();
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      storage.readReply.complete(jsonEncode(_credentials(expiresAt: 1)));
      await initializing;
      expect(client.auth.currentSession, isNull);
      expect(events, [
        CollectAuthEvent.tokenRefreshed,
        CollectAuthEvent.signedOut,
      ]);
      expect(storage.clears, 1);
    },
  );

  test(
    'concurrent initialize waits for the restored refresh to persist',
    () async {
      final storage = _InitializationStorage()
        ..writeRelease = Completer<void>();
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/auth/refresh');
          entered.complete();
          return reply.future;
        }),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        if (!reply.isCompleted) reply.complete(_json({}, 401));
        if (!storage.writeRelease!.isCompleted)
          storage.writeRelease!.complete();
        await client.dispose();
      });
      final initializing = client.initialize();
      await storage.readStarted.future;
      storage.readReply.complete(jsonEncode(_credentials(expiresAt: 1)));
      await entered.future;
      final whileRefreshing = client.initialize();
      expect(identical(initializing, whileRefreshing), isTrue);
      reply.complete(_json(_credentials(refresh: 'refreshed-synthetic')));
      await storage.writeStarted.future;
      final whilePersisting = client.initialize();
      expect(identical(initializing, whilePersisting), isTrue);
      storage.writeRelease!.complete();
      await Future.wait([initializing, whileRefreshing, whilePersisting]);
      expect(client.auth.currentSession?.isExpired, isFalse);
      expect(storage.reads, 1);
    },
  );

  for (final failure in ['read', 'clear']) {
    test('current initialization $failure failure remains visible', () async {
      final storage = _InitializationStorage()..clearFails = failure == 'clear';
      final client = CollectCloudflareClient(
        'https://api.example.com',
        sessionStorage: storage,
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected network'),
        ),
      );
      addTearDown(() async {
        if (!storage.readReply.isCompleted) storage.readReply.complete(null);
        await client.dispose();
      });
      final initializing = client.initialize();
      final rejected = expectLater(initializing, throwsStateError);
      await storage.readStarted.future;
      if (failure == 'read') {
        storage.readReply.completeError(StateError('Synthetic read failure'));
      } else {
        storage.readReply.complete('{invalid');
      }
      await rejected;
      expect(client.auth.currentSession, isNull);
    });
  }

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

final class _InitializationStorage implements CollectAuthSessionStorage {
  final readStarted = Completer<void>();
  final readReply = Completer<String?>();
  final clearStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Completer<void>? clearRelease;
  Completer<void>? writeRelease;
  bool clearFails = false, writeFails = false;
  String? value;
  int reads = 0, clears = 0, writes = 0;
  final operations = <String>[];

  @override
  Future<String?> read() {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    return readReply.future;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    operations.add('write');
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeRelease case final release?) await release.future;
    if (writeFails) throw StateError('Synthetic write failure');
    this.value = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    operations.add('clear:start');
    if (!clearStarted.isCompleted) clearStarted.complete();
    if (clearRelease case final release?) await release.future;
    if (clearFails) {
      operations.add('clear:failed');
      throw StateError('Synthetic clear failure');
    }
    value = null;
    operations.add('clear:end');
  }
}

final class _BarrierStorage implements CollectAuthSessionStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

final class _FailingStorage implements CollectAuthSessionStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async => throw StateError('Key unavailable');
  @override
  Future<void> clear() async {}
}
