import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_email_verification_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_mfa.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/admin_mfa_intent_storage.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;
import '../support/legacy_backend_fixture.dart';

const _admin = '11111111-1111-4111-8111-111111111111';
const _principal = '22222222-2222-4222-8222-222222222222';
const _factor = '33333333-3333-4333-8333-333333333333';
const _challenge = '44444444-4444-4444-8444-444444444444';
Map<String, dynamic> _user({int aal = 1}) => {
  'user': {
    'id': _admin,
    'principalId': _principal,
    'email': 'operator@example.test',
    'role': 'owner',
    'sessionId': 'public-cookie-session',
    'permissions': ['auth.mfa.enroll', 'account.manage'],
    'assuranceLevel': aal,
    'mfaAt': aal == 2 ? DateTime.now().toUtc().toIso8601String() : null,
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
};
http.Response _json(Object value) => http.Response(jsonEncode(value), 200);
CloudflareAdminSession _session(
  Future<http.Response> Function(http.Request) handler,
) => CloudflareAdminSession(
  MockClient(handler),
  origin: Uri.parse('https://admin.example.test'),
  environment: legacyBackendFixtureEnvironment,
);
const _pending = CloudflareAdminMfaFactor(
  id: _factor,
  name: 'Authenticator',
  verified: false,
);

const _supabaseSid = '55555555-5555-4555-8555-555555555555';

CloudflareAdminSession _emailSession({
  required List<http.Request> requests,
  DateTime? emailVerifiedAt,
  bool mfaAvailable = false,
  bool mfaRequired = false,
  List<String>? permissions,
  Future<http.Response> Function(http.Request)? onRequest,
}) => CloudflareAdminSession(
  MockClient((request) async {
    requests.add(request);
    if (request.url.path.endsWith('/auth/session')) {
      expect(request.method, 'GET');
      final response = _user();
      final user = response['user'] as Map<String, dynamic>;
      user['sessionId'] = _supabaseSid;
      user['email'] = 'info@ikanisa.com';
      if (mfaAvailable) {
        user['mfaAvailable'] = true;
        user['permissions'] = ['account.manage'];
      }
      if (mfaRequired) user['mfaRequired'] = true;
      if (permissions != null) user['permissions'] = permissions;
      response['ownerEmail'] = 'info@ikanisa.com';
      response['csrfToken'] = 'a' * 64;
      return _json(response);
    }
    if (request.url.path.endsWith('/auth/email-verification')) {
      expect(request.method, 'GET');
      return _json({
        'contractVersion': 1,
        'sessionId': _supabaseSid,
        'emailVerifiedAt': emailVerifiedAt?.toIso8601String(),
      });
    }
    if (onRequest != null) return onRequest(request);
    throw StateError(
      'Unexpected transport: ${request.method} ${request.url.path}',
    );
  }),
  origin: Uri.parse('https://admin.collect.ikanisa.com'),
  environment: fixtures.environment(),
);

GoRouter _mfaRouter({
  String initialLocation = '/admin/security/authenticator',
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/admin/security/verify-email',
      builder: (_, _) =>
          const Scaffold(body: CloudflareAdminEmailVerificationPage()),
    ),
    GoRoute(
      path: '/admin/security/authenticator',
      builder: (_, _) => const Scaffold(body: CloudflareAdminMfaPage()),
    ),
    GoRoute(
      path: '/admin/security',
      builder: (_, _) => const Scaffold(body: Text('Account security')),
    ),
  ],
);

Widget _mfaApp(CloudflareAdminSession session, GoRouter router) =>
    ProviderScope(
      overrides: [
        cloudflareAdminSessionProvider.overrideWith((ref) => session),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );

void _expectNoAuthenticatorControls() {
  for (final key in [
    'cloudflare_admin_mfa_setup',
    'cloudflare_admin_mfa_secret',
    'cloudflare_admin_mfa_code',
    'cloudflare_admin_mfa_verify',
    'cloudflare_admin_mfa_cancel',
    'cloudflare_admin_mfa_enroll',
  ]) {
    expect(find.byKey(ValueKey(key)), findsNothing);
  }
  for (final label in [
    'Authenticator',
    'Setup key',
    'Authenticator code',
    'Verify code',
    'Cancel pending setup',
    'Connect authenticator',
  ]) {
    expect(find.text(label), findsNothing);
  }
}

void main() {
  test(
    'server MFA denials name the authenticator for writes and evidence',
    () async {
      final session = _emailSession(
        requests: <http.Request>[],
        emailVerifiedAt: DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        ),
        permissions: const ['payments.evidence.read', 'sms.read', 'sms.reveal'],
        onRequest: (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'mfa_required'},
          }),
          403,
        ),
      );
      addTearDown(session.dispose);
      await session.refresh();
      await expectLater(
        session.request('protected', authenticated: true),
        throwsA(
          isA<CloudflareAdminRequestException>()
              .having((e) => e.code, 'code', 'mfa_required')
              .having(
                (e) => e.message,
                'message',
                'Verify your authenticator before making this change.',
              ),
        ),
      );
      await expectLater(
        session.retainedEvidence(
          _factor,
          sha256Hex: 'a' * 64,
          sizeBytes: 1,
          sourceSensitivity: 'raw_sms',
          reviewReason: 'Review a synthetic source',
        ),
        throwsA(
          isA<CloudflareAdminRequestException>()
              .having((e) => e.code, 'code', 'mfa_required')
              .having(
                (e) => e.message,
                'message',
                'Verify your authenticator before revealing SMS-source evidence.',
              ),
        ),
      );
    },
  );

  test('mandatory MFA requires current email and authenticator proofs', () {
    final now = DateTime.now().toUtc();
    CloudflareAdminUser user({DateTime? email, DateTime? mfa, int aal = 1}) =>
        CloudflareAdminUser(
          id: _admin,
          email: 'operator@example.test',
          role: AdminAccountRole.owner,
          sessionId: _supabaseSid,
          expiresAt: now.add(const Duration(hours: 1)),
          permissions: const [
            'payments.evidence.read',
            'sms.read',
            'sms.reveal',
          ],
          usesEmailVerification: true,
          emailVerifiedAt: email,
          mfaRequired: true,
          mfaAt: mfa,
          assuranceLevel: aal,
        );
    final recent = now.subtract(const Duration(seconds: 1));
    final stale = now.subtract(const Duration(minutes: 6));
    expect(
      user(email: recent).hasRecentSensitiveVerification(now: now),
      isFalse,
    );
    expect(
      user(email: recent, mfa: recent).hasRecentSensitiveVerification(now: now),
      isFalse,
    );
    expect(
      user(
        email: stale,
        mfa: recent,
        aal: 2,
      ).hasRecentSensitiveVerification(now: now),
      isFalse,
    );
    expect(
      user(
        email: recent,
        mfa: stale,
        aal: 2,
      ).hasRecentSensitiveVerification(now: now),
      isFalse,
    );
    expect(
      user(
        email: recent,
        mfa: recent,
        aal: 2,
      ).hasRecentSensitiveVerification(now: now),
      isTrue,
    );
    expect(
      () => requireRetainedEvidenceReviewAccess(user(email: recent)),
      throwsA(
        isA<CloudflareAdminRequestException>().having(
          (e) => e.code,
          'code',
          'mfa_required',
        ),
      ),
    );
  });

  testWidgets(
    'verified email continues to authenticator when mandatory MFA is pending',
    (tester) async {
      final session = _emailSession(
        requests: <http.Request>[],
        emailVerifiedAt: DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        ),
        mfaAvailable: true,
        mfaRequired: true,
        onRequest: (request) async => _json({'id': _principal, 'factors': []}),
      );
      await session.refresh();
      final router = _mfaRouter(
        initialLocation: '/admin/security/verify-email',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_mfaApp(session, router));
      await tester.pumpAndSettle();
      expect(find.text('Continue to authenticator'), findsOneWidget);
      await tester.tap(find.text('Continue to authenticator'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/security/authenticator',
      );
      expect(find.text('Authenticator'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'real verification requires a fresh server session readback and fences earlier cookie requests',
    () async {
      final held = Completer<http.Response>();
      var aal = 1;
      var verifications = 0;
      final session = _session((request) async {
        expect(request.url.origin, 'https://admin.example.test');
        if (request.url.path.endsWith('/auth/session')) {
          return _json(_user(aal: aal));
        }
        if (request.url.path.endsWith('/protected')) return held.future;
        if (request.url.path.endsWith('/auth/mfa/challenge')) {
          expect(jsonDecode(request.body), {'factor_id': _factor});
          return _json({
            'id': _challenge,
            'challenge_id': _challenge,
            'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
          });
        }
        expect(request.url.path, '/api/admin/auth/mfa/verify');
        expect(jsonDecode(request.body), {
          'factor_id': _factor,
          'challenge_id': _challenge,
          'code': '123456',
        });
        verifications++;
        aal = 2;
        return _json({'ok': true});
      });
      addTearDown(session.dispose);
      await session.refresh();
      final old = session.request('protected', authenticated: true);
      final denial = expectLater(
        old,
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      await CloudflareAdminMfaApi(session).verify(_pending, '123456');
      expect(session.user!.assuranceLevel, 2);
      expect(verifications, 1);
      held.complete(_json({'private': 'stale-cookie-response'}));
      await denial;
    },
  );

  test('an ok verification response alone cannot grant AAL2', () async {
    final session = _session(
      (request) async => request.url.path.endsWith('/auth/session')
          ? _json(_user())
          : _json({'ok': true, 'user': _user(aal: 2)['user']}),
    );
    addTearDown(session.dispose);
    await session.refresh();
    await expectLater(
      session.verifyAuthenticator(
        factorId: _factor,
        challengeId: _challenge,
        code: '123456',
      ),
      throwsA(isA<CloudflareAdminRequestException>()),
    );
    expect(session.user!.assuranceLevel, 1);
  });

  for (final candidateCookieArrived in [false, true]) {
    test('lost authenticator response recovers the same session '
        '(candidate cookie arrived: $candidateCookieArrived)', () async {
      var verified = false;
      var recoveryCalls = 0;
      var sessionReads = 0;
      String? verificationId;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            sessionReads++;
            if (verified && !candidateCookieArrived && recoveryCalls == 0) {
              return http.Response(
                jsonEncode({
                  'error': {'code': 'mfa_recovery_pending'},
                }),
                409,
              );
            }
            final response = _user(aal: verified ? 2 : 1);
            final current = response['user'] as Map<String, dynamic>;
            current['sessionId'] = _supabaseSid;
            current['email'] = 'info@ikanisa.com';
            current['permissions'] = ['account.manage'];
            current['mfaAvailable'] = true;
            response['ownerEmail'] = 'info@ikanisa.com';
            response['csrfToken'] = 'a' * 64;
            return _json(response);
          }
          if (request.url.path.endsWith('/auth/email-verification')) {
            return _json({
              'contractVersion': 1,
              'sessionId': _supabaseSid,
              'emailVerifiedAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
          if (request.url.path.endsWith('/auth/mfa/verify')) {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['factor_id'], _factor);
            expect(payload['challenge_id'], _challenge);
            verificationId = payload['verification_id'] as String?;
            expect(verificationId, matches(RegExp(r'^[a-f0-9]{64}$')));
            verified = true;
            return http.Response(
              jsonEncode({
                'error': {'code': 'mfa_operation_unknown'},
              }),
              503,
            );
          }
          if (request.url.path.endsWith('/auth/mfa/recover')) {
            recoveryCalls++;
            expect(jsonDecode(request.body), {
              'factor_id': _factor,
              'challenge_id': _challenge,
              'verification_id': verificationId,
            });
            return _json({'ok': true});
          }
          throw StateError('Unexpected request ${request.url.path}');
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
        mfaRecoveryDelay: (duration) async {
          expect(duration, const Duration(seconds: 26));
        },
      );
      addTearDown(session.dispose);
      await session.refresh();
      await session.verifyAuthenticator(
        factorId: _factor,
        challengeId: _challenge,
        code: '123456',
      );
      expect(session.user!.assuranceLevel, 2);
      expect(recoveryCalls, candidateCookieArrived ? 0 : 1);
      expect(sessionReads, 3);
    });
  }

  test('a cleared session cancels a pending authenticator recovery', () async {
    final wait = Completer<void>();
    final dispatched = Completer<void>();
    var recoveryCalls = 0;
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/session')) {
          final response = _user();
          final current = response['user'] as Map<String, dynamic>;
          current['sessionId'] = _supabaseSid;
          current['email'] = 'info@ikanisa.com';
          current['permissions'] = ['account.manage'];
          current['mfaAvailable'] = true;
          response['ownerEmail'] = 'info@ikanisa.com';
          response['csrfToken'] = 'a' * 64;
          return _json(response);
        }
        if (request.url.path.endsWith('/auth/email-verification')) {
          return _json({
            'contractVersion': 1,
            'sessionId': _supabaseSid,
            'emailVerifiedAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
        if (request.url.path.endsWith('/auth/mfa/verify')) {
          dispatched.complete();
          return http.Response(
            jsonEncode({
              'error': {'code': 'mfa_operation_unknown'},
            }),
            503,
          );
        }
        if (request.url.path.endsWith('/auth/mfa/recover')) {
          recoveryCalls++;
          return _json({'ok': true});
        }
        throw StateError('Unexpected request ${request.url.path}');
      }),
      origin: Uri.parse('https://admin.collect.ikanisa.com'),
      environment: fixtures.environment(),
      mfaRecoveryDelay: (_) => wait.future,
    );
    addTearDown(session.dispose);
    await session.refresh();
    final action = session.verifyAuthenticator(
      factorId: _factor,
      challengeId: _challenge,
      code: '123456',
    );
    final denial = expectLater(
      action,
      throwsA(isA<CloudflareAdminRequestException>()),
    );
    await dispatched.future;
    session.clear();
    wait.complete();
    await denial;
    expect(recoveryCalls, 0);
    expect(session.user, isNull);
  });

  for (final replacementCookie in [false, true]) {
    test(
      'same-tab reload restores the retained intent (replacement cookie: $replacementCookie)',
      () async {
        final storage = MemoryAdminMfaIntentStorage();
        final hold = Completer<void>();
        final dispatched = Completer<void>();
        var outcomePending = false;
        var recoveryCalls = 0;
        String? verificationId;
        Future<http.Response> handler(http.Request request) async {
          if (request.url.path.endsWith('/auth/session')) {
            if (outcomePending && recoveryCalls == 0 && !replacementCookie) {
              return http.Response(
                jsonEncode({
                  'error': {'code': 'mfa_recovery_pending'},
                }),
                409,
              );
            }
            final response = _user(
              aal: recoveryCalls > 0 || (outcomePending && replacementCookie)
                  ? 2
                  : 1,
            );
            final current = response['user'] as Map<String, dynamic>;
            current['sessionId'] = _supabaseSid;
            current['email'] = 'info@ikanisa.com';
            current['permissions'] = ['account.manage'];
            current['mfaAvailable'] = true;
            response['ownerEmail'] = 'info@ikanisa.com';
            response['csrfToken'] = 'a' * 64;
            return _json(response);
          }
          if (request.url.path.endsWith('/auth/email-verification')) {
            return _json({
              'contractVersion': 1,
              'sessionId': _supabaseSid,
              'emailVerifiedAt': DateTime.now().toUtc().toIso8601String(),
            });
          }
          if (request.url.path.endsWith('/auth/mfa/verify')) {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            verificationId = payload['verification_id'] as String;
            outcomePending = true;
            dispatched.complete();
            return http.Response(
              jsonEncode({
                'error': {'code': 'mfa_operation_unknown'},
              }),
              503,
            );
          }
          if (request.url.path.endsWith('/auth/mfa/recover')) {
            recoveryCalls++;
            expect(request.headers.containsKey('X-Collect-CSRF'), isFalse);
            expect(jsonDecode(request.body), {
              'factor_id': _factor,
              'challenge_id': _challenge,
              'verification_id': verificationId,
            });
            return _json({'ok': true});
          }
          throw StateError('Unexpected request ${request.url.path}');
        }

        final original = CloudflareAdminSession(
          MockClient(handler),
          origin: Uri.parse('https://admin.collect.ikanisa.com'),
          environment: fixtures.environment(),
          mfaIntentStorage: storage,
          mfaRecoveryDelay: (_) => hold.future,
        );
        await original.refresh();
        final action = original.verifyAuthenticator(
          factorId: _factor,
          challengeId: _challenge,
          code: '123456',
        );
        final denial = expectLater(
          action,
          throwsA(isA<CloudflareAdminRequestException>()),
        );
        await dispatched.future;
        original.dispose();
        hold.complete();
        await denial;
        expect(storage.read()?.verificationId, verificationId);
        expect(storage.read()!.toJson().containsKey('code'), isFalse);
        final reloaded = CloudflareAdminSession(
          MockClient(handler),
          origin: Uri.parse('https://admin.collect.ikanisa.com'),
          environment: fixtures.environment(),
          mfaIntentStorage: storage,
          mfaRecoveryDelay: (_) async {},
        );
        addTearDown(reloaded.dispose);
        await reloaded.refresh();
        expect(reloaded.user?.assuranceLevel, 2);
        expect(recoveryCalls, replacementCookie ? 0 : 1);
        expect(storage.read(), isNull);
      },
    );
  }

  test('another tab cannot recover an intent it did not initiate', () async {
    var recoveryCalls = 0;
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/mfa/recover')) recoveryCalls++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'mfa_recovery_pending'},
          }),
          409,
        );
      }),
      origin: Uri.parse('https://admin.collect.ikanisa.com'),
      environment: fixtures.environment(),
      mfaIntentStorage: MemoryAdminMfaIntentStorage(),
      mfaRecoveryDelay: (_) async {},
    );
    addTearDown(session.dispose);
    await session.refresh();
    expect(session.user, isNull);
    expect(recoveryCalls, 0);
  });

  test('expired and malformed tab intents cannot start recovery', () async {
    final storage = MemoryAdminMfaIntentStorage();
    storage.write(
      AdminMfaRecoveryIntent(
        factorId: _factor,
        challengeId: _challenge,
        verificationId: 'a' * 64,
        sessionId: _supabaseSid,
        userId: _admin,
        startingAssuranceLevel: 1,
        startingMfaAtMillis: null,
        createdAtMillis: DateTime.now()
            .subtract(const Duration(minutes: 6))
            .millisecondsSinceEpoch,
      ),
    );
    expect(
      () => AdminMfaRecoveryIntent.parse({
        ...storage.read()!.toJson(),
        'verification_id': 'short',
      }),
      throwsFormatException,
    );
    expect(
      () => AdminMfaRecoveryIntent.parse({
        ...storage.read()!.toJson(),
        'unexpected': true,
      }),
      throwsFormatException,
    );
    var recoveryCalls = 0;
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/mfa/recover')) recoveryCalls++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'mfa_recovery_pending'},
          }),
          409,
        );
      }),
      origin: Uri.parse('https://admin.collect.ikanisa.com'),
      environment: fixtures.environment(),
      mfaIntentStorage: storage,
      mfaRecoveryDelay: (_) async {},
    );
    addTearDown(session.dispose);
    await session.refresh();
    expect(session.user, isNull);
    expect(recoveryCalls, 0);
  });

  test(
    'manual sign-out after reload uses the retained intent when CSRF is not yet loaded',
    () async {
      final storage = MemoryAdminMfaIntentStorage();
      storage.write(
        AdminMfaRecoveryIntent(
          factorId: _factor,
          challengeId: _challenge,
          verificationId: 'a' * 64,
          sessionId: _supabaseSid,
          userId: _admin,
          startingAssuranceLevel: 1,
          startingMfaAtMillis: null,
          createdAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      var logoutCalls = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          expect(request.url.path, endsWith('/auth/logout'));
          expect(request.headers.containsKey('X-Collect-CSRF'), isFalse);
          expect(jsonDecode(request.body), {
            'factor_id': _factor,
            'challenge_id': _challenge,
            'verification_id': 'a' * 64,
          });
          logoutCalls++;
          return _json({'ok': true});
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
        mfaIntentStorage: storage,
      );
      addTearDown(session.dispose);
      await session.signOut();
      expect(logoutCalls, 1);
      expect(session.user, isNull);
      expect(storage.read(), isNull);
    },
  );

  test('an older AAL2 proof cannot confirm a lost new verification', () async {
    final previousProof = DateTime.now().toUtc().subtract(
      const Duration(minutes: 2),
    );
    var recoveryCalls = 0;
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/session')) {
          final response = _user(aal: 2);
          final current = response['user'] as Map<String, dynamic>;
          current['sessionId'] = _supabaseSid;
          current['email'] = 'info@ikanisa.com';
          current['permissions'] = ['account.manage'];
          current['mfaAvailable'] = true;
          current['mfaAt'] = previousProof.toIso8601String();
          response['ownerEmail'] = 'info@ikanisa.com';
          response['csrfToken'] = 'a' * 64;
          return _json(response);
        }
        if (request.url.path.endsWith('/auth/email-verification')) {
          return _json({
            'contractVersion': 1,
            'sessionId': _supabaseSid,
            'emailVerifiedAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
        if (request.url.path.endsWith('/auth/mfa/verify')) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'mfa_operation_unknown'},
            }),
            503,
          );
        }
        if (request.url.path.endsWith('/auth/mfa/recover')) {
          recoveryCalls++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'mfa_recovery_unavailable'},
            }),
            409,
          );
        }
        throw StateError('Unexpected request ${request.url.path}');
      }),
      origin: Uri.parse('https://admin.collect.ikanisa.com'),
      environment: fixtures.environment(),
      mfaRecoveryDelay: (_) async {},
    );
    addTearDown(session.dispose);
    await session.refresh();
    await expectLater(
      session.verifyAuthenticator(
        factorId: _factor,
        challengeId: _challenge,
        code: '123456',
      ),
      throwsA(isA<CloudflareAdminRequestException>()),
    );
    expect(recoveryCalls, 1);
    expect(session.user?.mfaAt, previousProof);
  });

  test('factor lookup refuses another canonical principal', () async {
    final session = _session(
      (request) async => request.url.path.endsWith('/auth/session')
          ? _json(_user())
          : _json({'id': _admin, 'factors': []}),
    );
    addTearDown(session.dispose);
    await session.refresh();
    await expectLater(
      CloudflareAdminMfaApi(session).factors(),
      throwsA(isA<AdminAccountException>()),
    );
  });

  test(
    'pending recovery is exact, and a verified factor never reaches cancellation transport',
    () async {
      var cancellations = 0;
      final session = _session((request) async {
        if (request.url.path.endsWith('/auth/session')) return _json(_user());
        expect(request.url.path, '/api/admin/auth/mfa/cancel-enrollment');
        expect(jsonDecode(request.body), {'factor_id': _factor});
        cancellations++;
        return _json({
          'id': _factor,
          'factor_type': 'totp',
          'status': 'revoked',
        });
      });
      addTearDown(session.dispose);
      await session.refresh();
      final api = CloudflareAdminMfaApi(session);
      await api.cancelPending(_pending);
      await expectLater(
        api.cancelPending(
          const CloudflareAdminMfaFactor(
            id: _factor,
            name: 'Authenticator',
            verified: true,
          ),
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(cancellations, 1);
    },
  );

  test(
    'setup rejects a deceptive authenticator destination and never accepts its secret',
    () {
      final user = CloudflareAdminUser.parse(_user());
      expect(
        () => CloudflareAdminMfaSetup.parse({
          'id': _factor,
          'factor_type': 'totp',
          'status': 'unverified',
          'totp': {
            'secret': 'A' * 32,
            'uri': 'https://evil.example/authenticator',
          },
        }, user),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );

  for (final withProof in [false, true]) {
    test(
      'Supabase AAL1 refuses every authenticator API before transport with ${withProof ? 'current' : 'absent'} email proof and legacy permission',
      () async {
        final proof = withProof
            ? DateTime.now().toUtc().subtract(const Duration(seconds: 1))
            : null;
        final requests = <http.Request>[];
        final session = _emailSession(
          requests: requests,
          emailVerifiedAt: proof,
        );
        addTearDown(session.dispose);
        await session.refresh();
        final actor = session.user!;
        final fence = session.authorityFence;
        expect(session.usesEmailVerification, isTrue);
        expect(actor.usesEmailVerification, isTrue);
        expect(actor.principalId, _principal);
        expect(actor.permissions, contains('auth.mfa.enroll'));
        expect(actor.sessionId, _supabaseSid);
        expect(actor.assuranceLevel, 1);
        expect(actor.mfaAt, isNull);
        expect(actor.emailVerifiedAt, proof);
        expect(requests.length, 2);
        final api = CloudflareAdminMfaApi(session);
        final operations = <String, Future<void> Function()>{
          'factors': () async {
            await api.factors();
          },
          'enroll': () async {
            await api.enroll();
          },
          'verify': () => api.verify(_pending, '123456'),
          'cancelPending': () => api.cancelPending(_pending),
        };
        for (final operation in operations.entries) {
          await expectLater(
            operation.value(),
            throwsA(
              isA<AdminAccountException>().having(
                (error) => error.message,
                'email guidance',
                'Verify your email to confirm sensitive changes.',
              ),
            ),
            reason: operation.key,
          );
          expect(requests.length, 2, reason: operation.key);
          expect(session.user, same(actor), reason: operation.key);
          expect(session.authorityFence, fence, reason: operation.key);
          expect(session.user!.sessionId, _supabaseSid);
          expect(session.user!.assuranceLevel, 1);
          expect(session.user!.mfaAt, isNull);
          expect(session.user!.emailVerifiedAt, proof);
        }
        expect(
          requests.map((request) => request.url.path.split('/auth/').last),
          ['session', 'email-verification'],
        );
      },
    );
  }

  test(
    'legacy factor lookup and enrollment retain their transport contracts',
    () async {
      final requests = <http.Request>[];
      final secret = 'A' * 32;
      final session = _session((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/session')) return _json(_user());
        if (request.url.path.endsWith('/auth/user')) {
          expect(request.method, 'GET');
          return _json({
            'id': _principal,
            'factors': [
              {
                'id': _factor,
                'factor_type': 'totp',
                'status': 'unverified',
                'friendly_name': 'Authenticator',
              },
            ],
          });
        }
        expect(request.url.path, '/api/admin/auth/mfa/enroll');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'friendly_name': 'Collect Admin',
          'factor_type': 'totp',
        });
        return _json({
          'id': _factor,
          'factor_type': 'totp',
          'status': 'unverified',
          'friendly_name': 'Authenticator',
          'totp': {
            'secret': secret,
            'uri': Uri(
              scheme: 'otpauth',
              host: 'totp',
              path: '/Collect:operator@example.test',
              queryParameters: {
                'secret': secret,
                'issuer': 'Collect',
                'algorithm': 'SHA1',
                'digits': '6',
                'period': '30',
              },
            ).toString(),
          },
        });
      });
      addTearDown(session.dispose);
      await session.refresh();
      final api = CloudflareAdminMfaApi(session);
      final factors = await api.factors();
      expect(factors, hasLength(1));
      expect(factors.single.id, _factor);
      expect(factors.single.verified, isFalse);
      final setup = await api.enroll();
      expect(setup.factor.id, _factor);
      expect(setup.factor.verified, isFalse);
      expect(setup.secret, secret);
      expect(requests.length, 3);
      expect(session.usesEmailVerification, isFalse);
      expect(session.user!.assuranceLevel, 1);
    },
  );

  test(
    'Supabase exposes the existing authenticator only when advertised',
    () async {
      final requests = <http.Request>[];
      final session = _emailSession(
        requests: requests,
        mfaAvailable: true,
        onRequest: (request) async {
          expect(
            request.url.path.endsWith('/api/admin/auth/mfa/factors'),
            isTrue,
          );
          expect(request.method, 'GET');
          return _json({'id': _principal, 'factors': []});
        },
      );
      addTearDown(session.dispose);
      await session.refresh();
      expect(session.user!.mfaAvailable, isTrue);
      expect(session.user!.permissions, isNot(contains('auth.mfa.enroll')));
      expect(await CloudflareAdminMfaApi(session).factors(), isEmpty);
      expect(
        requests.last.url.path.endsWith('/api/admin/auth/mfa/factors'),
        isTrue,
      );
    },
  );

  testWidgets('advertised Supabase authenticator uses the existing screen', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final session = _emailSession(
      requests: requests,
      mfaAvailable: true,
      onRequest: (request) async {
        expect(
          request.url.path.endsWith('/api/admin/auth/mfa/factors'),
          isTrue,
        );
        return _json({'id': _principal, 'factors': []});
      },
    );
    await session.refresh();
    final router = _mfaRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_mfaApp(session, router));
    await tester.pumpAndSettle();
    expect(find.text('Authenticator'), findsOneWidget);
    expect(find.text('Connect authenticator'), findsOneWidget);
    expect(find.text('Verify email'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replayed authenticator code asks for a new code', (
    tester,
  ) async {
    final session = _emailSession(
      requests: <http.Request>[],
      mfaAvailable: true,
      onRequest: (request) async {
        if (request.url.path.endsWith('/auth/mfa/factors')) {
          return _json({
            'id': _principal,
            'factors': [
              {
                'id': _factor,
                'factor_type': 'totp',
                'status': 'verified',
                'friendly_name': 'Authenticator',
              },
            ],
          });
        }
        if (request.url.path.endsWith('/auth/mfa/challenge')) {
          return _json({
            'id': _challenge,
            'challenge_id': _challenge,
            'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90,
          });
        }
        expect(request.url.path.endsWith('/auth/mfa/verify'), isTrue);
        return http.Response(
          jsonEncode({
            'error': {'code': 'mfa_code_already_used'},
          }),
          429,
        );
      },
    );
    await session.refresh();
    final router = _mfaRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_mfaApp(session, router));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cloudflare_admin_mfa_code')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('cloudflare_admin_mfa_verify')));
    await tester.pumpAndSettle();
    expect(find.text('Wait for a new authenticator code.'), findsOneWidget);
    expect(session.user!.assuranceLevel, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'direct Supabase authenticator page uses email verification and sends only the existing email request',
    (tester) async {
      final requests = <http.Request>[];
      final session = _emailSession(
        requests: requests,
        onRequest: (request) async {
          expect(request.url.path.endsWith('/auth/email/request'), isTrue);
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), <String, dynamic>{});
          expect(request.headers['X-Collect-CSRF'], 'a' * 64);
          return http.Response(
            jsonEncode({
              'challenge_id': _challenge,
              'retry_after': 60,
              'expires_in': 300,
              'delivery_status': 'accepted',
            }),
            202,
          );
        },
      );
      await session.refresh();
      final actor = session.user!;
      final fence = session.authorityFence;
      expect(actor.permissions, contains('auth.mfa.enroll'));
      final router = _mfaRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_mfaApp(session, router));
      await tester.pumpAndSettle();
      expect(find.text('Verify email'), findsOneWidget);
      expect(find.text('Send email code'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      _expectNoAuthenticatorControls();
      expect(
        requests.length,
        2,
        reason: 'Opening the page must not load factors or send email.',
      );
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      expect(requests.length, 3);
      expect(requests.last.url.path.endsWith('/auth/email/request'), isTrue);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Email code'), findsOneWidget);
      _expectNoAuthenticatorControls();
      expect(session.user, same(actor));
      expect(session.authorityFence, fence);
      expect(session.user!.sessionId, _supabaseSid);
      expect(session.user!.assuranceLevel, 1);
      expect(session.user!.mfaAt, isNull);
      expect(session.user!.emailVerifiedAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'direct Supabase authenticator page with current email proof continues to account security at AAL1',
    (tester) async {
      final proof = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      final requests = <http.Request>[];
      final session = _emailSession(requests: requests, emailVerifiedAt: proof);
      await session.refresh();
      final actor = session.user!;
      final router = _mfaRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_mfaApp(session, router));
      await tester.pumpAndSettle();
      expect(
        find.text('Your email is verified for sensitive changes.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Send email code'), findsNothing);
      _expectNoAuthenticatorControls();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/security');
      expect(find.text('Account security'), findsOneWidget);
      expect(requests.length, 2);
      expect(session.user, same(actor));
      expect(session.user!.sessionId, _supabaseSid);
      expect(session.user!.assuranceLevel, 1);
      expect(session.user!.mfaAt, isNull);
      expect(session.user!.emailVerifiedAt, proof);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('legacy authenticator page still offers Connect authenticator', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final session = _session((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/auth/session')) return _json(_user());
      expect(request.url.path, '/api/admin/auth/user');
      expect(request.method, 'GET');
      return _json({'id': _principal, 'factors': []});
    });
    await session.refresh();
    final router = _mfaRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_mfaApp(session, router));
    await tester.pumpAndSettle();
    expect(find.text('Authenticator'), findsOneWidget);
    expect(find.text('Connect authenticator'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloudflare_admin_mfa_enroll')),
      findsOneWidget,
    );
    expect(find.text('Verify email'), findsNothing);
    expect(find.text('Send email code'), findsNothing);
    expect(requests.length, 2);
    expect(session.usesEmailVerification, isFalse);
    expect(session.user!.assuranceLevel, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
