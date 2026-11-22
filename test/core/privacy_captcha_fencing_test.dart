import 'dart:async';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../features/privacy/privacy_test_support.dart';

void main() {
  test(
    'account change during a browser challenge prevents privacy OTP dispatch',
    () async {
      final candidate = Completer<String>();
      final started = Completer<void>();
      var current = true, calls = 0;
      final transport = CollectPrivacyRequestTransport(
        apiUrl: 'https://synthetic.invalid',
        captchaRequired: true,
        captchaProvider: () {
          started.complete();
          return candidate.future;
        },
        isSessionCurrent: (_) => current,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{"challenge_id":"synthetic-challenge"}', 200);
        }),
      );
      final owner = PrivacySessionSnapshot.parse(privacySession(), 1)!;
      final sending = transport.sendCode(owner);
      final assertion = expectLater(
        sending,
        throwsA(
          isA<PrivacyRequestException>().having(
            (e) => e.failure,
            'session fence',
            PrivacyFailure.sessionChanged,
          ),
        ),
      );
      await started.future;
      current = false;
      candidate.complete('SYNTHETIC_CANDIDATE');
      await assertion;
      expect(calls, 0);
    },
  );

  test(
    'disposing an old controller cannot cancel a new owner challenge',
    () async {
      final oldCandidate = Completer<String>(),
          newCandidate = Completer<String>();
      var challengeCount = 0, cancelled = 0, requests = 0;
      final transport = CollectPrivacyRequestTransport(
        apiUrl: 'https://synthetic.invalid',
        captchaRequired: true,
        captchaProvider: () =>
            ++challengeCount == 1 ? oldCandidate.future : newCandidate.future,
        cancelCaptcha: () {
          cancelled++;
        },
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{"challenge_id":"synthetic-challenge"}', 200);
        }),
      );
      final oldOwner = PrivacySessionSnapshot.parse(privacySession(), 1)!;
      final newOwner = PrivacySessionSnapshot.parse(
        privacySession(subject: privacyOtherSubject),
        2,
      )!;
      final oldSending = transport.sendCode(oldOwner);
      final assertion = expectLater(
        oldSending,
        throwsA(
          isA<PrivacyRequestException>().having(
            (e) => e.failure,
            'old attempt',
            PrivacyFailure.cancelled,
          ),
        ),
      );
      final newSending = transport.sendCode(newOwner);
      transport.cancelVerification(oldOwner);
      oldCandidate.complete('SYNTHETIC_OLD_CANDIDATE');
      newCandidate.complete('SYNTHETIC_NEW_CANDIDATE');
      await assertion;
      await newSending;
      expect(cancelled, 0);
      expect(requests, 1);
      transport.cancelVerification(newOwner);
      expect(cancelled, 1);
    },
  );
}
