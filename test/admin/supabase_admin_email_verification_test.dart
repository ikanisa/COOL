import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_return_location.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

const _sid = '00000000-0000-4000-8000-000000000001';
const _challenge = '00000000-0000-4000-8000-000000000002';
final _csrf = 'a' * 64;
Map<String, dynamic> _account() => {
  'user': {
    'id': '00000000-0000-4000-8000-000000000003',
    'principalId': '00000000-0000-4000-8000-000000000004',
    'email': 'info@ikanisa.com',
    'role': 'owner',
    'sessionId': _sid,
    'permissions': ['overview.read', 'account.manage', 'admin_users.manage'],
    'assuranceLevel': 1,
    'mfaAt': null,
    'financialModel': 'canonical_evidence_ledger',
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'ownerEmail': 'info@ikanisa.com',
  'csrfToken': _csrf,
};
Map<String, dynamic> _proof(Object? at) => {
  'contractVersion': 1,
  'sessionId': _sid,
  'emailVerifiedAt': at,
};
Map<String, dynamic> _receipt({
  int expires = 300,
  String delivery = 'accepted',
}) => {
  'challenge_id': _challenge,
  'retry_after': 60,
  'expires_in': expires,
  'delivery_status': delivery,
};
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);
String _recent() => DateTime.now()
    .toUtc()
    .subtract(const Duration(seconds: 1))
    .toIso8601String();
CloudflareAdminSession _client(
  FutureOr<http.Response> Function(http.Request) handler,
) => CloudflareAdminSession(
  MockClient((request) async => handler(request)),
  origin: Uri.parse('https://admin.collect.ikanisa.com'),
  environment: fixtures.environment(),
);

void main() {
  test(
    'same-session proof authorizes sensitive work without changing actor, AAL or CSRF',
    () async {
      Object? at;
      final requests = <http.Request>[];
      final client = _client((request) {
        requests.add(request);
        if (request.url.path.endsWith('/auth/session')) {
          return _json(_account());
        }
        if (request.url.path.endsWith('/auth/email/request')) {
          return _json(_receipt(), 202);
        }
        if (request.url.path.endsWith('/auth/email/verify')) {
          at = _recent();
          return _json(_proof(at));
        }
        return _json(_proof(at));
      });
      addTearDown(client.dispose);
      await client.refresh();
      final before = client.authorityFence;
      expect(
        CloudflareAdminAccountApi(client).invitationManagementAuthorized,
        isFalse,
      );
      final receipt = await client.requestSensitiveEmailVerification();
      expect(client.authorityFence, before);
      await client.verifySensitiveEmailVerification(
        challengeId: receipt.challengeId,
        code: '123456',
      );
      expect(client.authorityFence, before);
      expect(client.user!.assuranceLevel, 1);
      expect(client.user!.mfaAt, isNull);
      expect(client.user!.sessionId, _sid);
      expect(
        CloudflareAdminAccountApi(client).invitationManagementAuthorized,
        isTrue,
      );
      final send = requests.singleWhere(
        (r) => r.url.path.endsWith('/auth/email/request'),
      );
      final verify = requests.singleWhere(
        (r) => r.url.path.endsWith('/auth/email/verify'),
      );
      expect(jsonDecode(send.body), isEmpty);
      expect(jsonDecode(verify.body), {
        'challenge_id': _challenge,
        'code': '123456',
      });
      expect(send.headers['X-Collect-CSRF'], _csrf);
      expect(verify.headers['X-Collect-CSRF'], _csrf);
      expect(requests.any((r) => r.url.path.endsWith('/auth/otp')), isFalse);
    },
  );

  for (final invalid in <String, Object?>{
    'missing': null,
    'stale': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 6))
        .toIso8601String(),
    'future': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
    'local time': '2026-01-01T00:00:00',
    'non-UTC': '2026-01-01T00:00:00+02:00',
    'number': 123,
  }.entries) {
    test(
      '${invalid.key} proof cannot authorize an ordinary AAL1 account',
      () async {
        final client = _client(
          (r) => _json(
            r.url.path.endsWith('/auth/session')
                ? _account()
                : _proof(invalid.value),
          ),
        );
        addTearDown(client.dispose);
        await client.refresh();
        expect(client.user, isNotNull);
        expect(client.user!.hasRecentSensitiveVerification(), isFalse);
        expect(
          CloudflareAdminAccountApi(client).invitationManagementAuthorized,
          isFalse,
        );
      },
    );
  }

  test(
    'unavailable or malformed proof preserves ordinary session and denies sensitive work',
    () async {
      var unavailable = true;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) {
          final body = _account();
          (body['user'] as Map)['emailVerifiedAt'] = _recent();
          return _json(body);
        }
        return unavailable
            ? _json({'error': 'unavailable'}, 503)
            : _json({..._proof(_recent()), 'csrfToken': 'b' * 64});
      });
      addTearDown(client.dispose);
      await client.refresh();
      expect(client.user!.hasRecentSensitiveVerification(), isFalse);
      unavailable = false;
      await client.refresh();
      expect(client.user, isNotNull);
      expect(client.user!.hasRecentSensitiveVerification(), isFalse);
    },
  );

  test('wrong public session identity is never installed', () async {
    final client = _client(
      (r) => _json(
        r.url.path.endsWith('/auth/session')
            ? _account()
            : {..._proof(_recent()), 'sessionId': _challenge},
      ),
    );
    addTearDown(client.dispose);
    await client.refresh();
    expect(client.user, isNull);
    expect(client.state.hasError, isTrue);
  });

  test(
    'wrong code is a typed denial; real session revocation logs out',
    () async {
      var status = 400;
      var sends = 0;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) return _json(_account());
        if (r.url.path.endsWith('/auth/email/request')) {
          return _json(_receipt(), 202);
        }
        if (r.url.path.endsWith('/auth/email/verify')) {
          sends++;
          return _json({
            'error': {
              'code': status == 400 ? 'invalid_credentials' : 'unauthenticated',
            },
          }, status);
        }
        return _json(_proof(null));
      });
      addTearDown(client.dispose);
      await client.refresh();
      await client.requestSensitiveEmailVerification();
      await expectLater(
        client.verifySensitiveEmailVerification(
          challengeId: _challenge,
          code: '123456',
        ),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(client.user, isNotNull);
      status = 401;
      await expectLater(
        client.verifySensitiveEmailVerification(
          challengeId: _challenge,
          code: '123456',
        ),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(sends, 2);
      expect(client.user, isNull);
    },
  );

  test(
    'unknown verification is not replayed and explicit read recovers genuine proof',
    () async {
      var verifications = 0;
      Object? at;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) return _json(_account());
        if (r.url.path.endsWith('/auth/email/request')) {
          return _json(_receipt(), 202);
        }
        if (r.url.path.endsWith('/auth/email/verify')) {
          verifications++;
          at = _recent();
          return _json({
            'error': {'code': 'admin_email_operation_unknown'},
          }, 503);
        }
        return _json(_proof(at));
      });
      addTearDown(client.dispose);
      await client.refresh();
      await client.requestSensitiveEmailVerification();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.verifySensitiveEmailVerification(
            challengeId: _challenge,
            code: '123456',
          ),
          throwsA(isA<AdminAccountException>()),
        );
      }
      expect(verifications, 1);
      expect(client.user, isNotNull);
      expect(await client.recheckSensitiveEmailVerification(), isTrue);
      expect(client.user!.assuranceLevel, 1);
      expect(verifications, 1);
    },
  );

  test(
    'unchanged old proof cannot reconcile an ambiguous renewal, even after leaving the page',
    () async {
      final old = DateTime.now().toUtc().subtract(const Duration(seconds: 20));
      Object? proof = old.toIso8601String();
      var sends = 0;
      var sessionUnavailable = false;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) {
          if (sessionUnavailable) {
            throw http.ClientException('temporary read failure');
          }
          return _json(_account());
        }
        if (r.url.path.endsWith('/auth/email/request')) {
          sends++;
          return _json(_receipt(), 202);
        }
        if (r.url.path.endsWith('/auth/email/verify')) {
          return _json({'error': 'admin_email_operation_unknown'}, 503);
        }
        return _json(_proof(proof));
      });
      addTearDown(client.dispose);
      await client.refresh();
      expect(client.user!.hasRecentSensitiveVerification(), isTrue);
      final fence = client.authorityFence;
      await client.requestSensitiveEmailVerification();
      await expectLater(
        client.verifySensitiveEmailVerification(
          challengeId: _challenge,
          code: '123456',
        ),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(client.user!.hasRecentSensitiveVerification(), isFalse);
      client.cancelSensitiveEmailVerification();
      await client.refresh();
      expect(client.sensitiveEmailVerificationUnconfirmed, isTrue);
      sessionUnavailable = true;
      await client.refresh();
      expect(client.state.hasError, isTrue);
      sessionUnavailable = false;
      await client.refresh();
      expect(client.sensitiveEmailVerificationUnconfirmed, isTrue);
      expect(await client.recheckSensitiveEmailVerification(), isFalse);
      expect(client.user!.hasRecentSensitiveVerification(), isFalse);
      await expectLater(
        client.requestSensitiveEmailVerification(),
        throwsA(isA<AdminAccountException>()),
      );
      expect(sends, 1);
      expect(client.user!.authorityKey, fence.key);
      final recoveredFence = client.authorityFence;
      proof = _recent();
      expect(await client.recheckSensitiveEmailVerification(), isTrue);
      expect(client.sensitiveEmailVerificationUnconfirmed, isFalse);
      expect(client.authorityFence, recoveredFence);
    },
  );

  for (final expiry in [0, 1, 300]) {
    test(
      'sensitive receipt accepts remaining expiry $expiry independently of normal sign-in',
      () async {
        final client = _client(
          (r) => _json(
            r.url.path.endsWith('/auth/session')
                ? _account()
                : r.url.path.endsWith('/auth/email/request')
                ? _receipt(expires: expiry)
                : _proof(null),
            r.url.path.endsWith('/auth/email/request') ? 202 : 200,
          ),
        );
        addTearDown(client.dispose);
        await client.refresh();
        expect(
          (await client.requestSensitiveEmailVerification()).expiresInSeconds,
          expiry,
        );
      },
    );
  }

  test(
    'unconfirmed successful SEND cannot rotate CSRF and cannot be automatically resent',
    () async {
      var sends = 0;
      final requests = <http.Request>[];
      final client = _client((r) {
        requests.add(r);
        if (r.url.path.endsWith('/auth/session')) return _json(_account());
        if (r.url.path.endsWith('/auth/email/request')) {
          sends++;
          return _json({..._receipt(), 'csrfToken': 'b' * 64}, 202);
        }
        return _json(_proof(null));
      });
      addTearDown(client.dispose);
      await client.refresh();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.requestSensitiveEmailVerification(),
          throwsA(isA<AdminAccountException>()),
        );
      }
      expect(sends, 1);
      await client.request(
        'synthetic-action',
        body: const {},
        authenticated: true,
      );
      expect(requests.last.headers['X-Collect-CSRF'], _csrf);
    },
  );

  for (final cancel in [true, false]) {
    test(
      '${cancel ? 'cancellation' : 'sign-out'} fences a late verification response',
      () async {
        final pending = Completer<http.Response>();
        final client = _client((r) {
          if (r.url.path.endsWith('/auth/session')) return _json(_account());
          if (r.url.path.endsWith('/auth/email/request')) {
            return _json(_receipt(), 202);
          }
          if (r.url.path.endsWith('/auth/email/verify')) return pending.future;
          return _json(_proof(null));
        });
        addTearDown(client.dispose);
        await client.refresh();
        await client.requestSensitiveEmailVerification();
        final rejected = expectLater(
          client.verifySensitiveEmailVerification(
            challengeId: _challenge,
            code: '123456',
          ),
          throwsA(isA<AdminAccountException>()),
        );
        if (cancel) {
          client.cancelSensitiveEmailVerification();
        } else {
          client.clear();
        }
        pending.complete(_json(_proof(_recent())));
        await rejected;
        expect(client.user?.hasRecentSensitiveVerification() ?? false, isFalse);
      },
    );
  }

  test(
    'older sidecar read cannot erase proof installed by a later completed verification',
    () async {
      final pendingRead = Completer<http.Response>();
      var reads = 0;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) return _json(_account());
        if (r.url.path.endsWith('/auth/email/request')) {
          return _json(_receipt(), 202);
        }
        if (r.url.path.endsWith('/auth/email/verify')) {
          return _json(_proof(_recent()));
        }
        if (++reads == 2) return pendingRead.future;
        return _json(_proof(null));
      });
      addTearDown(client.dispose);
      await client.refresh();
      await client.requestSensitiveEmailVerification();
      final refresh = client.refresh();
      await Future<void>.delayed(Duration.zero);
      await client.verifySensitiveEmailVerification(
        challengeId: _challenge,
        code: '123456',
      );
      pendingRead.complete(_json(_proof(null)));
      await refresh;
      expect(client.user!.hasRecentSensitiveVerification(), isTrue);
    },
  );

  test(
    'only dedicated refresh contention receives two bounded read retries',
    () async {
      var reads = 0;
      var code = 'session_refresh_pending';
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/session')) return _json(_account());
        if (++reads < 3 || code != 'session_refresh_pending') {
          return _json({
            'error': {'code': code},
          }, 409);
        }
        return _json(_proof(_recent()));
      });
      addTearDown(client.dispose);
      await client.refresh();
      expect(reads, 3);
      expect(client.user!.hasRecentSensitiveVerification(), isTrue);
      code = 'other_conflict';
      reads = 0;
      await client.refresh();
      expect(reads, 1);
      expect(client.user, isNotNull);
      expect(client.user!.hasRecentSensitiveVerification(), isFalse);
    },
  );

  for (final staleRead in [true, false]) {
    test(
      'late 401 from ${staleRead ? 'superseded metadata' : 'cancelled verification'} cannot clear current session',
      () async {
        final pending = Completer<http.Response>();
        var reads = 0;
        final client = _client((r) {
          if (r.url.path.endsWith('/auth/session')) return _json(_account());
          if (r.url.path.endsWith('/auth/email/request')) {
            return _json(_receipt(), 202);
          }
          if (r.url.path.endsWith('/auth/email/verify')) {
            return staleRead ? _json(_proof(_recent())) : pending.future;
          }
          if (++reads == 2 && staleRead) return pending.future;
          return _json(_proof(null));
        });
        addTearDown(client.dispose);
        await client.refresh();
        await client.requestSensitiveEmailVerification();
        Future<void> old;
        if (staleRead) {
          old = client.refresh();
          await Future<void>.delayed(Duration.zero);
          await client.verifySensitiveEmailVerification(
            challengeId: _challenge,
            code: '123456',
          );
        } else {
          old = expectLater(
            client.verifySensitiveEmailVerification(
              challengeId: _challenge,
              code: '123456',
            ),
            throwsA(isA<AdminAccountException>()),
          );
          client.cancelSensitiveEmailVerification();
        }
        pending.complete(_json({'error': 'unauthenticated'}, 401));
        await old;
        expect(client.user, isNotNull);
        expect(client.user!.hasRecentSensitiveVerification(), staleRead);
      },
    );
  }

  test(
    'verification return location is internal, loop-free and strips sensitive query data',
    () {
      for (final raw in [
        'https://evil.test/admin',
        '//evil.test/admin',
        '/admin/login',
        '/admin/setup?token=secret',
        '/admin/security/verify-email',
        '/admin/security/authenticator',
        '/admin/a/../login',
        '/admin/a%2Fb',
      ]) {
        expect(
          cloudflareAdminEmailVerificationReturnLocation(raw),
          isNull,
          reason: raw,
        );
      }
      expect(
        cloudflareAdminEmailVerificationReturnLocation(
          '/admin/payments?token=secret&claim=opaque',
        ),
        '/admin/payments',
      );
      expect(
        cloudflareAdminEmailVerificationReturnLocation(
          '/admin/requests?key=opaque-request-1&code=123456',
        ),
        '/admin/requests?key=opaque-request-1',
      );
      expect(
        cloudflareAdminEmailVerificationReturnLocation(
          '/admin/requests?key=opaque-request-1&key=second-key',
        ),
        '/admin/requests',
      );
    },
  );

  test(
    'superseded normal OTP confirmation cannot clear a newer same-session refresh',
    () async {
      final oldConfirmation = Completer<http.Response>();
      final confirmationStarted = Completer<void>();
      var sessionReads = 0;
      final client = _client((r) {
        if (r.url.path.endsWith('/auth/otp')) return _json(_receipt(), 202);
        if (r.url.path.endsWith('/auth/verify')) return _json(_account());
        if (r.url.path.endsWith('/auth/session')) {
          if (++sessionReads == 1) {
            confirmationStarted.complete();
            return oldConfirmation.future;
          }
          return _json(_account());
        }
        return _json(_proof(_recent()));
      });
      addTearDown(client.dispose);
      await client.requestEmailOtp('info@ikanisa.com');
      final rejected = expectLater(
        client.verifyEmailOtp(
          email: 'info@ikanisa.com',
          challengeId: _challenge,
          code: '123456',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      await confirmationStarted.future;
      await client.refresh();
      expect(client.user, isNotNull);
      final confirmed = client.authorityFence;
      oldConfirmation.complete(
        _json({
          'error': {'code': 'unauthenticated'},
        }, 401),
      );
      await rejected;
      expect(client.user, isNotNull);
      expect(client.authorityFence, confirmed);
      expect(client.user!.sessionId, _sid);
      expect(client.user!.assuranceLevel, 1);
    },
  );
}
