import 'dart:convert';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'privacy_test_support.dart';

void main() {
  final session = PrivacySessionSnapshot.parse(privacySession(), 0)!;
  const canary = 'PRIVATE_PROVIDER_BODY';

  CollectPrivacyRequestTransport transport(int status, Object body) {
    final client = MockClient((request) async {
      expect(
        request.headers['Authorization'],
        'Bearer ${session.session.accessToken}',
      );
      return http.Response(jsonEncode(body), status);
    });
    addTearDown(client.close);
    return CollectPrivacyRequestTransport(
      httpClient: client,
      apiUrl: 'https://synthetic.invalid',
    );
  }

  Matcher fails(PrivacyFailure failure) => throwsA(
    isA<PrivacyRequestException>()
        .having((error) => error.failure, 'fixed failure', failure)
        .having(
          (error) => error.toString(),
          'no private body',
          isNot(contains(canary)),
        ),
  );

  for (final refusal in <(int, String, PrivacyFailure)>[
    (401, 'authentication_required', PrivacyFailure.sessionChanged),
    (401, 'invalid_token', PrivacyFailure.sessionChanged),
    (401, 'access_revoked', PrivacyFailure.sessionChanged),
    (403, 'session_changed', PrivacyFailure.sessionChanged),
    (403, 'fresh_auth_required', PrivacyFailure.freshSignInRequired),
    (409, 'privacy_request_conflict', PrivacyFailure.conflictingRequest),
    (409, 'request_conflict', PrivacyFailure.conflictingRequest),
    (404, 'privacy_request_unavailable', PrivacyFailure.requestUnavailable),
  ]) {
    test('canonical privacy refusal ${refusal.$2} is actionable', () async {
      final api = transport(refusal.$1, {
        'code': refusal.$2,
        'message': canary,
        'request_id': 'server-correlation-id',
      });
      await expectLater(
        api.submit(session, privacySubmission, 'reason'),
        fails(refusal.$3),
      );
    });
    test(
      'gateway failure carrying ${refusal.$2} cannot prove rejection',
      () async {
        final api = transport(503, {'code': refusal.$2, 'message': canary});
        await expectLater(
          api.submit(session, privacySubmission, 'reason'),
          fails(PrivacyFailure.outcomeUnknown),
        );
      },
    );
  }

  for (final refusal in <(int, String, PrivacyFailure)>[
    (400, 'captcha_required', PrivacyFailure.captchaRequired),
    (400, 'captcha_failed', PrivacyFailure.captchaRequired),
    (401, 'invalid_credentials', PrivacyFailure.invalidCode),
  ]) {
    test('canonical OTP refusal ${refusal.$2} gives safe recovery', () async {
      final api = transport(refusal.$1, {
        'code': refusal.$2,
        'message': canary,
      });
      await expectLater(api.sendCode(session), fails(refusal.$3));
    });
  }

  test('read denial cannot invent intake or erasure completion', () async {
    final api = transport(401, {'code': 'access_revoked', 'message': canary});
    await expectLater(
      api.currentStatus(session),
      fails(PrivacyFailure.sessionChanged),
    );
  });
  test('unrecognized refusal preserves an uncertain submission', () async {
    final api = transport(409, {
      'code': 'unknown_gateway_code',
      'message': canary,
    });
    await expectLater(
      api.submit(session, privacySubmission, 'reason'),
      fails(PrivacyFailure.outcomeUnknown),
    );
  });
}
