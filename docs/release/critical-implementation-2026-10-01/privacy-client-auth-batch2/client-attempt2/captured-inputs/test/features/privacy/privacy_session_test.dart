// Tests the internal bridges of the installed pinned GoTrue implementation.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_test_support.dart';

void main() {
  GoTrueClient client() => GoTrueClient(
    url: 'https://synthetic.invalid/auth/v1',
    autoRefreshToken: false,
    httpClient: MockClient((_) async => throw StateError('Unexpected network')),
  );

  test(
    'pinned recoverSession synchronously saves valid same-user session, with no SDK event',
    () async {
      final auth = client();
      addTearDown(auth.dispose);
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      final events = <AuthState>[];
      final subscription = auth.onAuthStateChangeSync.listen(events.add);
      addTearDown(subscription.cancel);
      final future = auth.recoverSession(
        jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      );
      expect(
        PrivacySessionSnapshot.parse(auth.currentSession, 0)!.sessionId,
        privacyNewSid,
      );
      expect(events, isEmpty);
      await future;
    },
  );
  test(
    'guarded adoption synchronously installs and publishes new ordinary member SID',
    () async {
      final auth = client();
      addTearDown(auth.dispose);
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = GoTruePrivacySessionAuthority(auth);
      addTearDown(authority.dispose);
      final before = authority.capture();
      final events = <AuthState>[];
      final sub = auth.onAuthStateChangeSync.listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      events.clear();
      final after = authority.adopt(before, privacySession(sid: privacyNewSid));
      expect(after.sessionId, privacyNewSid);
      expect(after.generation, greaterThan(before.generation));
      expect(events.single.event, AuthChangeEvent.signedIn);
    },
  );
  test(
    'actual global verifyOTP mutates before returning and can overwrite newer user',
    () async {
      final auth = GoTrueClient(
        url: 'https://synthetic.invalid/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(privacySession(sid: privacyNewSid).toJson()),
            200,
          ),
        ),
      );
      addTearDown(auth.dispose);
      await auth.recoverSession(
        jsonEncode(privacySession(subject: privacyOtherSubject).toJson()),
      );
      final result = await auth.verifyOTP(
        phone: '+250788000001',
        token: '123456',
        type: OtpType.sms,
      );
      expect(result.session!.user.id, privacySubject);
      expect(auth.currentUser!.id, privacySubject);
    },
  );
  test(
    'account ABA invalidates a captured generation even when UID and SID return',
    () async {
      final auth = client();
      addTearDown(auth.dispose);
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = GoTruePrivacySessionAuthority(auth);
      addTearDown(authority.dispose);
      final original = authority.capture();
      await auth.recoverSession(
        jsonEncode(privacySession(subject: privacyOtherSubject).toJson()),
      );
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      expect(authority.capture().sameFence(original), isFalse);
      expect(
        () => authority.adopt(original, privacySession(sid: privacyNewSid)),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(authority.capture().sessionId, privacyOldSid);
    },
  );
  test(
    'logout-start invalidation survives token refresh of the same SID',
    () async {
      final auth = client();
      addTearDown(auth.dispose);
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = GoTruePrivacySessionAuthority(auth);
      addTearDown(authority.dispose);
      final original = authority.capture();
      authority.invalidate();
      auth.notifyAllSubscribers(AuthChangeEvent.tokenRefreshed);
      expect(
        () => authority.capture(),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(
        () => authority.adopt(original, privacySession(sid: privacyNewSid)),
        throwsA(isA<PrivacyRequestException>()),
      );
      await auth.recoverSession(
        jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      );
      auth.notifyAllSubscribers(AuthChangeEvent.signedIn);
      expect(authority.capture().sessionId, privacyNewSid);
    },
  );
  final invalid = <String, Session Function()>{
    'wrong user': () =>
        privacySession(subject: privacyOtherSubject, sid: privacyNewSid),
    'same SID': () => privacySession(),
    'expired': () => privacySession(sid: privacyNewSid, exp: 1),
    'string exp': () =>
        privacySession(sid: privacyNewSid, claimExpiration: '9999999999'),
    'wrong subject claim': () =>
        privacySession(sid: privacyNewSid, claimSubject: privacyOtherSubject),
    'malformed SID': () =>
        privacySession(sid: privacyNewSid, claimSid: 'invalid'),
    'service role': () =>
        privacySession(sid: privacyNewSid, role: 'service_role'),
    'anonymous': () => privacySession(sid: privacyNewSid, anonymous: true),
    'missing refresh': () => privacySession(sid: privacyNewSid, refresh: null),
  };
  for (final entry in invalid.entries) {
    test(
      'adoption refuses ${entry.key} without touching live account',
      () async {
        final auth = client();
        addTearDown(auth.dispose);
        await auth.recoverSession(jsonEncode(privacySession().toJson()));
        final authority = GoTruePrivacySessionAuthority(auth);
        addTearDown(authority.dispose);
        final original = authority.capture();
        expect(
          () => authority.adopt(original, entry.value()),
          throwsA(isA<PrivacyRequestException>()),
        );
        expect(auth.currentSession!.accessToken, original.session.accessToken);
      },
    );
  }
}
