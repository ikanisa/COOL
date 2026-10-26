import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;
import '../core/supabase_google_auth_test.dart' as google;

const origin = 'https://platform-admin.collect.ikanisa.com';
Map<String, dynamic> account() => {
  'ownerEmail': 'info@ikanisa.com',
  'user': {
    'id': 'approved-staff-fixture',
    'email': 'staff@example.invalid',
    'role': 'staff',
    'sessionId': 'public-google-session',
    'permissions': <String>[],
    'assuranceLevel': 1,
    'mfaAt': null,
    'principalId': fixtures.principal,
    'financialModel': 'canonical_evidence_ledger',
  },
  'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
  'csrfToken': 'd' * 64,
};
CloudflareAdminSession controller(
  Future<http.Response> Function(http.Request) send,
) => CloudflareAdminSession(
  MockClient(send),
  origin: Uri.parse(origin),
  googleAuthEnabled: true,
  environment: fixtures.environment(api: origin, admin: origin),
);

void main() {
  test(
    'QA Admin Google keeps both callback hops on the selected QA origin',
    () async {
      const qa = 'https://admin-supabase-qa.collect.ikanisa.com';
      final calls = <http.Request>[];
      late String clientState;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          calls.add(request);
          expect(request.url.origin, qa);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          if (request.url.path.endsWith('/google/start')) {
            final body = jsonDecode(request.body) as Map;
            clientState = body['client_state'] as String;
            expect(body['return_origin'], qa);
            final url = google.authorizeUrl(
              redirect:
                  '$qa/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}',
            );
            return http.Response(
              jsonEncode({'authorization_url': url.toString()}),
              200,
            );
          }
          if (request.url.path.endsWith('/google/exchange')) {
            final body = jsonDecode(request.body) as Map;
            expect(body['client_state'], clientState);
            expect(body['code_verifier'], matches(r'^[A-Za-z0-9_-]{43}$'));
          } else {
            expect(
              request.url.path.endsWith('/auth/session') ||
                  request.url.path.endsWith('/auth/email-verification'),
              isTrue,
            );
          }
          if (request.url.path.endsWith('/auth/email-verification')) {
            return http.Response(
              jsonEncode({
                'contractVersion': 1,
                'sessionId': (account()['user'] as Map)['sessionId'],
                'emailVerifiedAt': null,
              }),
              200,
            );
          }
          return http.Response(jsonEncode(account()), 200);
        }),
        origin: Uri.parse(qa),
        googleAuthEnabled: true,
        environment: fixtures.environment(api: qa, admin: qa),
      );
      addTearDown(session.dispose);
      expect(session.googleSignInAvailable, isTrue);
      await session.signInWithGoogle(
        authorize: (createUrl, state, callbackOrigin) async {
          expect(callbackOrigin, qa);
          await createUrl(qa);
          expect(state, clientState);
          return {'code': 'c' * 43, 'state': state};
        },
      );
      expect(calls.length, 4);
      expect(session.user?.principalId, fixtures.principal);
      expect(session.user?.assuranceLevel, 1);
      expect(session.user?.mfaAt, isNull);
    },
  );

  test(
    'QA Admin rejects a production callback before Google exchange',
    () async {
      const qa = 'https://admin-supabase-qa.collect.ikanisa.com';
      var calls = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          calls++;
          expect(request.url.path.endsWith('/google/start'), isTrue);
          return http.Response(
            jsonEncode({'authorization_url': google.authorizeUrl().toString()}),
            200,
          );
        }),
        origin: Uri.parse(qa),
        googleAuthEnabled: true,
        environment: fixtures.environment(api: qa, admin: qa),
      );
      addTearDown(session.dispose);
      await expectLater(
        session.signInWithGoogle(
          authorize: (createUrl, state, callbackOrigin) async {
            await createUrl(qa);
            fail('Cross-environment callback must not produce a handoff.');
          },
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, 1);
      expect(session.user, isNull);
    },
  );

  test(
    'Google Admin admission rejects unapproved or mixed API origins',
    () async {
      const qa = 'https://admin-supabase-qa.collect.ikanisa.com';
      for (final pair in [
        ('https://unapproved.invalid', 'https://unapproved.invalid'),
        (qa, origin),
        (origin, qa),
      ]) {
        var calls = 0;
        final session = CloudflareAdminSession(
          MockClient((_) async {
            calls++;
            return http.Response('{}', 500);
          }),
          origin: Uri.parse(pair.$1),
          googleAuthEnabled: true,
          environment: fixtures.environment(api: pair.$2, admin: pair.$2),
        );
        expect(session.googleSignInAvailable, isFalse);
        await expectLater(
          session.signInWithGoogle(authorize: (_, _, _) async => {}),
          throwsA(isA<AdminAccountException>()),
        );
        expect(calls, 0);
        session.dispose();
      }
    },
  );

  test(
    'explicit session recheck confirms AAL1 session and separate proof metadata',
    () async {
      var calls = 0;
      final session = controller((request) async {
        calls++;
        expect(request.method, 'GET');
        expect(
          request.url.path.endsWith('/auth/session') ||
              request.url.path.endsWith('/auth/email-verification'),
          isTrue,
        );
        if (request.url.path.endsWith('/auth/email-verification')) {
          return http.Response(
            jsonEncode({
              'contractVersion': 1,
              'sessionId': (account()['user'] as Map)['sessionId'],
              'emailVerifiedAt': null,
            }),
            200,
          );
        }
        return http.Response(jsonEncode(account()), 200);
      });
      addTearDown(session.dispose);
      final api = CloudflareAdminAccountApi(session);
      expect(await api.recheckSession(), isTrue);
      expect(session.user?.assuranceLevel, 1);
      expect(calls, 2);
    },
  );

  test(
    'explicit session recheck unlocks only a confirmed signed-out result',
    () async {
      var calls = 0;
      final session = controller((request) async {
        calls++;
        expect(request.method, 'GET');
        return http.Response(
          jsonEncode({
            'user': null,
            'expiresAt': null,
            'ownerEmail': 'info@ikanisa.com',
            'csrfToken': null,
          }),
          200,
        );
      });
      addTearDown(session.dispose);
      expect(
        await CloudflareAdminAccountApi(session).recheckSession(),
        isFalse,
      );
      expect(session.user, isNull);
      expect(calls, 1);
    },
  );

  test(
    'failed session recheck remains uncertain and cannot become signed out',
    () async {
      var calls = 0;
      final session = controller((_) async {
        calls++;
        return http.Response(jsonEncode({'code': 'backend_unavailable'}), 503);
      });
      addTearDown(session.dispose);
      await expectLater(
        CloudflareAdminAccountApi(session).recheckSession(),
        throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
      );
      expect(session.user, isNull);
      expect(calls, 1);
    },
  );

  test('malformed or non-200 session reads never confirm signed out', () async {
    final signedOut = {
      'user': null,
      'expiresAt': null,
      'ownerEmail': 'info@ikanisa.com',
      'csrfToken': null,
    };
    for (final response in [
      http.Response('{}', 200),
      http.Response(jsonEncode({'code': 'backend_unavailable'}), 200),
      http.Response('{', 200),
      http.Response(jsonEncode({'user': null}), 200),
      http.Response(
        jsonEncode({...signedOut, 'expiresAt': '2026-10-20T00:00:00Z'}),
        200,
      ),
      http.Response(jsonEncode(signedOut), 202),
      http.Response(jsonEncode(signedOut), 401),
    ]) {
      var calls = 0;
      final session = controller((request) async {
        calls++;
        expect(request.method, 'GET');
        return response;
      });
      try {
        await expectLater(
          CloudflareAdminAccountApi(session).recheckSession(),
          throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
        );
        expect(calls, 1);
      } finally {
        session.dispose();
      }
    }
  });

  test(
    'superseded session recheck cannot report a confirmed sign-out',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final session = controller((_) {
        calls++;
        return response.future;
      });
      addTearDown(session.dispose);
      final check = CloudflareAdminAccountApi(session).recheckSession();
      await Future<void>.delayed(Duration.zero);
      session.clear();
      response.complete(
        http.Response(jsonEncode({'user': null, 'csrfToken': null}), 200),
      );
      await expectLater(
        check,
        throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'optional Google facade stays unavailable by default and cannot send auth requests',
    () async {
      var calls = 0;
      final session = CloudflareAdminSession(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
        origin: Uri.parse(origin),
        environment: fixtures.environment(api: origin, admin: origin),
      );
      addTearDown(session.dispose);
      final api = CloudflareAdminAccountApi(session);
      expect(api, isA<AdminGoogleAccountApi>());
      expect(api.googleSignInAvailable, isFalse);
      await expectLater(
        api.signInWithGoogle(authorize: (_, _, _) async => const {}),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'Admin Google exchanges handoff for cookie metadata then verifies current AAL1 session',
    () async {
      final calls = <http.Request>[];
      final result = account();
      late String clientState;
      final session = controller((request) async {
        calls.add(request);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        if (request.url.path.endsWith('/google/start')) {
          final body = jsonDecode(request.body) as Map;
          clientState = body['client_state'] as String;
          expect(body['return_origin'], origin);
          return http.Response(
            jsonEncode({'authorization_url': google.authorizeUrl().toString()}),
            200,
          );
        }
        if (request.url.path.endsWith('/google/exchange')) {
          final body = jsonDecode(request.body) as Map;
          expect(body['client_state'], clientState);
          expect(body['code_verifier'], matches(r'^[A-Za-z0-9_-]{43}$'));
          expect(request.headers['X-Collect-Requested-With'], 'collect-admin');
          return http.Response(jsonEncode(result), 200);
        }
        if (request.url.path.endsWith('/auth/email-verification')) {
          return http.Response(
            jsonEncode({
              'contractVersion': 1,
              'sessionId': (result['user'] as Map)['sessionId'],
              'emailVerifiedAt': null,
            }),
            200,
          );
        }
        expect(request.url.path.endsWith('/auth/session'), isTrue);
        return http.Response(jsonEncode(result), 200);
      });
      addTearDown(session.dispose);
      await session.signInWithGoogle(
        authorize: (createUrl, state, callbackOrigin) async {
          expect(callbackOrigin, collectSupabaseGoogleCallbackOrigin);
          await createUrl(origin);
          expect(state, clientState);
          return {'code': 'c' * 43, 'state': state};
        },
      );
      expect(calls.length, 4);
      expect(session.user?.email, 'staff@example.invalid');
      expect(session.user?.assuranceLevel, 1);
      expect(session.user?.mfaAt, isNull);
    },
  );

  test(
    'unknown Google exchange checks session once and never replays the handoff',
    () async {
      final calls = <http.Request>[];
      final session = controller((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/google/start')) {
          return http.Response(
            jsonEncode({'authorization_url': google.authorizeUrl().toString()}),
            200,
          );
        }
        if (request.url.path.endsWith('/google/exchange')) {
          return http.Response(
            jsonEncode({'code': 'google_sign_in_unconfirmed'}),
            503,
          );
        }
        return http.Response(
          jsonEncode({'user': null, 'csrfToken': null}),
          200,
        );
      });
      addTearDown(session.dispose);
      await expectLater(
        session.signInWithGoogle(
          authorize: (createUrl, state, _) async {
            await createUrl(origin);
            return {'code': 'c' * 43, 'state': state};
          },
        ),
        throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
      );
      expect(
        calls.where((r) => r.url.path.endsWith('/google/exchange')).length,
        1,
      );
      expect(
        calls.where((r) => r.url.path.endsWith('/auth/session')).length,
        1,
      );
      expect(session.user, isNull);
    },
  );

  test(
    'cancelled Google attempt and native Admin return cannot reach exchange',
    () async {
      final calls = <http.Request>[];
      final session = controller((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({'authorization_url': google.authorizeUrl().toString()}),
          200,
        );
      });
      addTearDown(session.dispose);
      await expectLater(
        session.signInWithGoogle(
          authorize: (createUrl, state, _) async {
            await createUrl(origin);
            session.cancelGoogleSignIn();
            return {'code': 'c' * 43, 'state': state};
          },
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls.length, 1);
      await expectLater(
        session.signInWithGoogle(
          authorize: (createUrl, state, _) async {
            await createUrl(null);
            return {'code': 'c' * 43, 'state': state};
          },
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls.length, 1);
    },
  );

  test(
    'successful unknown Admin OTP delivery reports uncertainty with a retained receipt',
    () async {
      final session = controller(
        (request) async => http.Response(
          jsonEncode({
            'challenge_id': 'fixture-admin-challenge',
            'retry_after': 60,
            'expires_in': 300,
            'delivery_status': 'unknown',
          }),
          200,
        ),
      );
      addTearDown(session.dispose);
      await expectLater(
        session.requestEmailOtp('staff@example.invalid'),
        throwsA(isA<AdminEmailOtpDeliveryUnknown>()),
      );
    },
  );

  test(
    'top-level backend errors preserve actual approval refusal code',
    () async {
      final session = controller(
        (request) async => http.Response(
          jsonEncode({'code': 'admin_access_not_approved'}),
          403,
        ),
      );
      addTearDown(session.dispose);
      await expectLater(
        session.request('auth/google/exchange', body: const {}),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.code,
            'code',
            'admin_access_not_approved',
          ),
        ),
      );
    },
  );
}
