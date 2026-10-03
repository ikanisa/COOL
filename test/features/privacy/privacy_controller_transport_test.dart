// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_test_support.dart';

Matcher fails(PrivacyFailure failure) => throwsA(
  isA<PrivacyRequestException>().having(
    (e) => e.failure,
    'fixed failure',
    failure,
  ),
);

class Harness {
  Harness._(this.auth, this.authority, this.controller, this.transport);
  final GoTrueClient auth;
  final GoTruePrivacySessionAuthority authority;
  final PrivacyRequestController controller;
  final SupabasePrivacyRequestTransport transport;

  static Future<Harness> create(
    Future<http.Response> Function(http.Request) callback, {
    bool captcha = false,
    Duration timeout = const Duration(seconds: 15),
    String? phone,
    String Function()? newId,
  }) async {
    final auth = GoTrueClient(
      url: 'https://synthetic.invalid/auth/v1',
      autoRefreshToken: false,
      httpClient: MockClient(
        (r) async => r.url.path.endsWith('/logout')
            ? http.Response('', 204)
            : throw StateError('No live Auth HTTP allowed'),
      ),
    );
    await auth.recoverSession(
      jsonEncode(privacySession(phone: phone ?? '+250788000001').toJson()),
    );
    final authority = GoTruePrivacySessionAuthority(auth);
    final transport = SupabasePrivacyRequestTransport(
      httpClient: MockClient(callback),
      supabaseUrl: 'https://synthetic.invalid',
      publishableKey: 'SYNTHETIC_PUBLIC_KEY',
      captchaRequired: captcha,
      timeout: timeout,
    );
    final controller = PrivacyRequestController(
      authority: authority,
      transport: transport,
      newSubmissionId: newId ?? () => privacySubmission,
    );
    final harness = Harness._(auth, authority, controller, transport);
    addTearDown(() async {
      controller.dispose();
      await authority.dispose();
      auth.dispose();
    });
    return harness;
  }

  Future<void> fresh() async {
    await controller.sendCode();
    await controller.verifyCode('123456');
  }

  Future<void> replace(Session session) async {
    await auth.recoverSession(jsonEncode(session.toJson()));
    auth.notifyAllSubscribers(AuthChangeEvent.signedIn);
  }
}

http.Response defaultResponse(http.Request request) {
  if (request.url.path.endsWith('/otp')) return http.Response('{}', 200);
  if (request.url.path.endsWith('/verify')) {
    return http.Response(
      jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      200,
    );
  }
  if (request.url.path.endsWith('/request_account_deletion_v1')) {
    return http.Response(jsonEncode(privacyReceiptJson(submission: true)), 200);
  }
  return http.Response(jsonEncode(privacyReceiptJson()), 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached receipt and pending identity are hidden after account switch or logout start',
    () async {
      final h = await Harness.create((r) async => defaultResponse(r));
      await h.fresh();
      await h.controller.submit(reason: 'reason');
      expect(h.controller.receipt, isNotNull);
      expect(h.controller.pendingIdentity, isNotNull);
      h.authority.invalidate();
      expect(h.controller.receipt, isNull);
      expect(h.controller.pendingIdentity, isNull);
      await h.replace(privacySession(subject: privacyOtherSubject));
      expect(h.controller.receipt, isNull);
      expect(h.controller.pendingIdentity, isNull);
    },
  );
  test(
    'cancelled submit can commit; only subsequent own status confirms it',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var writes = 0;
      final h = await Harness.create((r) async {
        if (r.url.path.endsWith('/request_account_deletion_v1')) {
          ++writes;
          started.complete();
          return response.future;
        }
        return defaultResponse(r);
      });
      await h.fresh();
      final submitting = h.controller.submit(reason: 'reason');
      await started.future;
      h.controller.cancel();
      final expected = expectLater(submitting, fails(PrivacyFailure.cancelled));
      response.complete(
        http.Response(jsonEncode(privacyReceiptJson(submission: true)), 200),
      );
      await expected;
      expect(h.controller.receipt, isNull);
      expect(h.controller.outcomeUnknown, isTrue);
      expect(h.controller.pendingIdentity!.submissionId, privacySubmission);
      await expectLater(
        h.controller.retrySubmission(reason: 'reason'),
        fails(PrivacyFailure.outcomeUnknown),
      );
      expect(
        (await h.controller.refreshStatus())!.requestId,
        privacySubmission,
      );
      expect(writes, 1);
    },
  );
  test(
    'verification requires a completed send and a valid six-digit OTP',
    () async {
      var calls = 0;
      final h = await Harness.create((r) async {
        ++calls;
        return defaultResponse(r);
      });
      await expectLater(
        h.controller.verifyCode('123456'),
        fails(PrivacyFailure.codeRequired),
      );
      await expectLater(
        h.controller.verifyCode('PRIVATE'),
        fails(PrivacyFailure.invalidCode),
      );
      expect(calls, 0);
    },
  );
  test(
    'existing captured subject OTP uses exact pinned wire contract and no live-client mutation',
    () async {
      final seen = <http.Request>[];
      final h = await Harness.create((request) async {
        seen.add(request);
        return defaultResponse(request);
      });
      await h.controller.sendCode(captchaToken: 'SYNTHETIC_CAPTCHA');
      expect(jsonDecode(seen.single.body), {
        'phone': '+250788000001',
        'data': {},
        'create_user': false,
        'gotrue_meta_security': {'captcha_token': 'SYNTHETIC_CAPTCHA'},
        'channel': 'whatsapp',
      });
      await h.controller.verifyCode(
        '123456',
        captchaToken: 'SYNTHETIC_CAPTCHA',
      );
      expect(jsonDecode(seen.last.body), {
        'phone': '+250788000001',
        'token': '123456',
        'type': 'sms',
        'redirect_to': null,
        'gotrue_meta_security': {'captcha_token': 'SYNTHETIC_CAPTCHA'},
      });
      for (final request in seen) {
        expect(request.headers['apikey'], 'SYNTHETIC_PUBLIC_KEY');
        expect(request.headers['authorization'], startsWith('Bearer '));
        expect(request.headers['x-supabase-api-version'], '2024-01-01');
        expect(request.followRedirects, isFalse);
      }
      expect(h.authority.capture().sessionId, privacyNewSid);
    },
  );
  for (final race in [
    'switch',
    'ABA',
    'logout',
    'logout-start',
    'cancel',
    'dispose',
    'new SID',
  ]) {
    test(
      'late OTP verification after $race never replaces current Auth',
      () async {
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final h = await Harness.create((request) async {
          if (request.url.path.endsWith('/verify')) {
            started.complete();
            return response.future;
          }
          return defaultResponse(request);
        });
        await h.controller.sendCode();
        final verifying = h.controller.verifyCode('123456');
        await started.future;
        switch (race) {
          case 'switch':
            await h.replace(privacySession(subject: privacyOtherSubject));
          case 'ABA':
            await h.replace(privacySession(subject: privacyOtherSubject));
            await h.replace(privacySession());
          case 'logout':
            h.authority.invalidate();
            await h.auth.signOut(scope: SignOutScope.local);
          case 'logout-start':
            h.authority.invalidate();
          case 'cancel':
            h.controller.cancel();
          case 'dispose':
            h.controller.dispose();
          case 'new SID':
            await h.replace(privacySession(sid: privacyCanonical));
        }
        final before = h.auth.currentSession?.accessToken;
        final expectation = expectLater(
          verifying,
          throwsA(isA<PrivacyRequestException>()),
        );
        response.complete(
          http.Response(
            jsonEncode(privacySession(sid: privacyNewSid).toJson()),
            200,
          ),
        );
        await expectation;
        expect(h.auth.currentSession?.accessToken, before);
        expect(h.controller.receipt, isNull);
      },
    );
  }
  test(
    'late send after cancellation cannot activate a verification challenge',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final h = await Harness.create((_) {
        started.complete();
        return response.future;
      });
      final sending = h.controller.sendCode();
      await started.future;
      h.controller.cancel();
      final expectation = expectLater(sending, fails(PrivacyFailure.cancelled));
      response.complete(http.Response('{}', 200));
      await expectation;
      expect(h.controller.codeSent, isFalse);
    },
  );
  test(
    'overlapping user actions are refused and only one OTP is sent',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final h = await Harness.create((_) {
        ++calls;
        return response.future;
      });
      final first = h.controller.sendCode();
      await expectLater(h.controller.sendCode(), fails(PrivacyFailure.busy));
      response.complete(http.Response('{}', 200));
      await first;
      expect(calls, 1);
    },
  );
  for (final candidate in <String, Session Function()>{
    'wrong subject': () =>
        privacySession(subject: privacyOtherSubject, sid: privacyNewSid),
    'different phone': () =>
        privacySession(sid: privacyNewSid, phone: '+250788000002'),
    'old SID': () => privacySession(),
    'expired': () => privacySession(sid: privacyNewSid, exp: 1),
    'missing refresh': () => privacySession(sid: privacyNewSid, refresh: null),
  }.entries) {
    test(
      'OTP response ${candidate.key} is refused without adopting Auth',
      () async {
        final h = await Harness.create(
          (r) async => r.url.path.endsWith('/verify')
              ? http.Response(jsonEncode(candidate.value().toJson()), 200)
              : defaultResponse(r),
        );
        await h.controller.sendCode();
        await expectLater(
          h.controller.verifyCode('123456'),
          fails(PrivacyFailure.verificationUnavailable),
        );
        expect(h.authority.capture().sessionId, privacyOldSid);
      },
    );
  }
  test(
    'explicit fresh OTP is required for a submit, even with a healthy old session',
    () async {
      var calls = 0;
      final h = await Harness.create((r) async {
        ++calls;
        return defaultResponse(r);
      });
      await expectLater(
        h.controller.submit(reason: 'reason'),
        fails(PrivacyFailure.freshSignInRequired),
      );
      expect(calls, 0);
    },
  );
  test(
    'actual typed RPC binds adopted token and stable UUID and permits one confirmed duplicate',
    () async {
      var submissions = 0;
      http.Request? observed;
      final h = await Harness.create((r) async {
        if (r.url.path.endsWith('/request_account_deletion_v1')) {
          ++submissions;
          observed = r;
        }
        return defaultResponse(r);
      });
      await h.fresh();
      final receipt = await h.controller.submit(reason: ' reason ');
      expect(jsonDecode(observed!.body), {
        'p_request_id': privacySubmission,
        'p_reason': 'reason',
      });
      expect(
        observed!.headers['authorization'],
        'Bearer ${h.auth.currentSession!.accessToken}',
      );
      expect(await h.controller.submit(reason: 'reason'), same(receipt));
      expect(submissions, 1);
      expect(receipt.erasureCompleted, isFalse);
    },
  );
  test(
    'response loss keeps UUID and explicit retry uses exact original payload',
    () async {
      var ids = 0;
      final bodies = <Object?>[];
      final h = await Harness.create(
        (r) async {
          if (!r.url.path.endsWith('/request_account_deletion_v1')) {
            return defaultResponse(r);
          }
          bodies.add(jsonDecode(r.body));
          if (bodies.length == 1) throw StateError('PRIVATE_PROVIDER_CANARY');
          return http.Response(
            jsonEncode(
              privacyReceiptJson(
                submission: true,
                replay: true,
                equivalent: true,
              ),
            ),
            200,
          );
        },
        newId: () {
          ++ids;
          return privacySubmission;
        },
      );
      await h.fresh();
      await expectLater(
        h.controller.submit(reason: 'reason'),
        fails(PrivacyFailure.outcomeUnknown),
      );
      await expectLater(
        h.controller.submit(reason: 'reason'),
        fails(PrivacyFailure.outcomeUnknown),
      );
      await expectLater(
        h.controller.retrySubmission(reason: 'changed'),
        fails(PrivacyFailure.conflictingRequest),
      );
      expect(
        (await h.controller.retrySubmission(reason: 'reason')).replay,
        isTrue,
      );
      expect(bodies, [
        {'p_request_id': privacySubmission, 'p_reason': 'reason'},
        {'p_request_id': privacySubmission, 'p_reason': 'reason'},
      ]);
      expect(ids, 1);
    },
  );
  test(
    'ambiguous commit resolves alias status without another write',
    () async {
      var writes = 0;
      http.Request? status;
      final h = await Harness.create((r) async {
        if (r.url.path.endsWith('/request_account_deletion_v1')) {
          ++writes;
          throw StateError('Lost response');
        }
        if (r.url.path.endsWith('/get_account_deletion_request_status_v1')) {
          status = r;
          return http.Response(
            jsonEncode(privacyReceiptJson(requestId: privacyCanonical)),
            200,
          );
        }
        return defaultResponse(r);
      });
      await h.fresh();
      await expectLater(
        h.controller.submit(reason: 'reason'),
        fails(PrivacyFailure.outcomeUnknown),
      );
      expect((await h.controller.refreshStatus())!.requestId, privacyCanonical);
      expect(jsonDecode(status!.body), {'p_request_id': privacySubmission});
      expect(writes, 1);
      expect(h.controller.outcomeUnknown, isFalse);
    },
  );
  test(
    'restart recovers canonical own receipt without UUID, reason or protected snapshot writes',
    () async {
      var protectedCalls = 0;
      final seen = <http.Request>[];
      const channel = MethodChannel('collect/secure_snapshot');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            ++protectedCalls;
            throw StateError('Financial cache must not be touched');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final h = await Harness.create((r) async {
        seen.add(r);
        return defaultResponse(r);
      });
      final recovered = await h.controller.refreshStatus();
      expect(recovered!.requestId, privacySubmission);
      expect(h.controller.pendingIdentity, isNull);
      expect(
        seen.single.url.path,
        '/rest/v1/rpc/get_current_account_deletion_request_status_v1',
      );
      expect(jsonDecode(seen.single.body), {});
      expect(protectedCalls, 0);
    },
  );
  test(
    'canonical null never confirms submission, cancellation or erasure',
    () async {
      final h = await Harness.create((_) async => http.Response('null', 200));
      expect(await h.controller.refreshStatus(), isNull);
      expect(h.controller.receipt, isNull);
      expect(h.controller.pendingIdentity, isNull);
    },
  );
  for (final operation in ['submit', 'status']) {
    test(
      'late $operation response after account switch is discarded, without clearing newer Auth',
      () async {
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final h = await Harness.create((r) async {
          if ((operation == 'submit' &&
                  r.url.path.endsWith('/request_account_deletion_v1')) ||
              (operation == 'status' &&
                  r.url.path.endsWith(
                    '/get_current_account_deletion_request_status_v1',
                  ))) {
            started.complete();
            return response.future;
          }
          return defaultResponse(r);
        });
        if (operation == 'submit') await h.fresh();
        final future = operation == 'submit'
            ? h.controller.submit(reason: 'reason')
            : h.controller.refreshStatus();
        await started.future;
        await h.replace(privacySession(subject: privacyOtherSubject));
        final expected = expectLater(
          future,
          fails(PrivacyFailure.sessionChanged),
        );
        response.complete(
          http.Response(
            jsonEncode(privacyReceiptJson(submission: operation == 'submit')),
            200,
          ),
        );
        await expected;
        expect(h.auth.currentUser!.id, privacyOtherSubject);
        expect(h.controller.receipt, isNull);
        await expectLater(
          h.controller.refreshStatus(),
          fails(PrivacyFailure.sessionChanged),
        );
      },
    );
  }
  test('missing trusted phone and captcha are refused before HTTP', () async {
    var calls = 0;
    final h = await Harness.create((r) async {
      ++calls;
      return defaultResponse(r);
    }, captcha: true);
    await expectLater(
      h.controller.sendCode(),
      fails(PrivacyFailure.captchaRequired),
    );
    expect(calls, 0);
    final noPhone = await Harness.create((r) async {
      ++calls;
      return defaultResponse(r);
    }, phone: 'profile phone');
    await expectLater(
      noPhone.controller.sendCode(),
      fails(PrivacyFailure.phoneUnavailable),
    );
    expect(calls, 0);
  });
  for (final error in <String, (int, Map<String, dynamic>, PrivacyFailure)>{
    'rate': (429, {'message': 'PRIVATE_CANARY'}, PrivacyFailure.rateLimited),
    'captcha': (
      400,
      {'code': 'captcha_failed', 'message': 'PRIVATE_CANARY'},
      PrivacyFailure.captchaRequired,
    ),
    'OTP': (
      400,
      {'code': 'otp_expired', 'message': 'PRIVATE_CANARY'},
      PrivacyFailure.invalidCode,
    ),
    'unknown': (
      500,
      {'message': 'PRIVATE_CANARY'},
      PrivacyFailure.verificationUnavailable,
    ),
  }.entries) {
    test('Auth error ${error.key} surfaces only fixed codes', () async {
      final h = await Harness.create(
        (_) async => http.Response(jsonEncode(error.value.$2), error.value.$1),
      );
      try {
        await h.controller.sendCode();
        fail('Expected failure');
      } on PrivacyRequestException catch (e) {
        expect(e.failure, error.value.$3);
        expect(e.toString(), isNot(contains('PRIVATE_CANARY')));
      }
    });
  }
  test(
    'server freshness refusal keeps request UUID and does not pretend acceptance',
    () async {
      final h = await Harness.create(
        (r) async => r.url.path.endsWith('/request_account_deletion_v1')
            ? http.Response(
                jsonEncode({
                  'code': '42501',
                  'message': 'privacy_request_fresh_session_required',
                  'details': 'PRIVATE_CANARY',
                }),
                403,
              )
            : defaultResponse(r),
      );
      await h.fresh();
      await expectLater(
        h.controller.submit(reason: 'reason'),
        fails(PrivacyFailure.freshSignInRequired),
      );
      expect(h.controller.receipt, isNull);
      expect(h.controller.pendingIdentity!.submissionId, privacySubmission);
    },
  );
  for (final kind in ['oversized', 'malformed', 'wrong submission', 'erased']) {
    test(
      'untrustworthy success $kind keeps ambiguous commit and UUID',
      () async {
        final h = await Harness.create((r) async {
          if (!r.url.path.endsWith('/request_account_deletion_v1')) {
            return defaultResponse(r);
          }
          final body = switch (kind) {
            'oversized' => List.filled(65537, 'x').join(),
            'malformed' => 'PRIVATE_CANARY',
            'wrong submission' => jsonEncode(
              privacyReceiptJson(
                submission: true,
                submissionId: privacyCanonical,
                equivalent: true,
              ),
            ),
            _ => jsonEncode(
              privacyReceiptJson(submission: true)
                ..['erasure_completed'] = true,
            ),
          };
          return http.Response(body, 200);
        });
        await h.fresh();
        await expectLater(
          h.controller.submit(reason: 'reason'),
          fails(PrivacyFailure.outcomeUnknown),
        );
        expect(h.controller.receipt, isNull);
        expect(h.controller.outcomeUnknown, isTrue);
        expect(h.controller.pendingIdentity!.submissionId, privacySubmission);
      },
    );
  }
  test(
    'bounded timeout discards late verification with no live Auth mutation',
    () async {
      final delayed = Completer<http.Response>();
      final h = await Harness.create(
        (r) async => r.url.path.endsWith('/verify')
            ? delayed.future
            : defaultResponse(r),
        timeout: const Duration(milliseconds: 10),
      );
      await h.controller.sendCode();
      await expectLater(
        h.controller.verifyCode('123456'),
        fails(PrivacyFailure.verificationUnavailable),
      );
      delayed.complete(
        http.Response(
          jsonEncode(privacySession(sid: privacyNewSid).toJson()),
          200,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.authority.capture().sessionId, privacyOldSid);
    },
  );
}
