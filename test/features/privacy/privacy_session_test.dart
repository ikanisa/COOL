import 'dart:convert';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'privacy_test_support.dart';

void main() {
  CollectCloudflareClient client() => CollectCloudflareClient(
    'https://synthetic.invalid',
    httpClient: MockClient((_) async => throw StateError('Unexpected network')),
  );

  test(
    'verified recovery installs synchronously and emits one owned event',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final events = <CollectAuthState>[];
      final subscription = backend.auth.onAuthStateChangeSync.listen(
        events.add,
      );
      addTearDown(subscription.cancel);
      final future = backend.auth.recoverSession(
        jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      );
      expect(
        PrivacySessionSnapshot.parse(backend.auth.currentSession, 0)!.sessionId,
        privacyNewSid,
      );
      expect(events.single.event, CollectAuthEvent.signedIn);
      await future;
    },
  );

  test(
    'guarded adoption publishes one event and advances the account fence',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(backend.auth);
      addTearDown(authority.dispose);
      final before = authority.capture();
      final events = <CollectAuthState>[];
      final subscription = backend.auth.onAuthStateChangeSync.listen(
        events.add,
      );
      addTearDown(subscription.cancel);
      final after = authority.adopt(before, privacySession(sid: privacyNewSid));
      expect(after.sessionId, privacyNewSid);
      expect(after.generation, greaterThan(before.generation));
      expect(events.single.event, CollectAuthEvent.signedIn);
    },
  );

  test(
    'account ABA invalidates capture even when user and session IDs return',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(backend.auth);
      addTearDown(authority.dispose);
      final original = authority.capture();
      final switched = backend.auth.recoverSession(
        jsonEncode(privacySession(subject: privacyOtherSubject).toJson()),
      );
      final returned = backend.auth.recoverSession(
        jsonEncode(privacySession().toJson()),
      );
      await Future.wait([switched, returned]);
      expect(authority.capture().sameFence(original), isFalse);
      expect(
        () => authority.adopt(original, privacySession(sid: privacyNewSid)),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(authority.capture().sessionId, privacyOldSid);
    },
  );

  test(
    'a foreign candidate cannot replace the currently owned account',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(backend.auth);
      addTearDown(authority.dispose);
      final original = authority.capture();
      expect(
        () => authority.adopt(
          original,
          privacySession(subject: privacyOtherSubject, sid: privacyNewSid),
        ),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(backend.auth.currentUser!.id, privacySubject);
      expect(authority.capture().sameFence(original), isTrue);
    },
  );

  test(
    'logout-start remains fenced across a same-session token notification',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(backend.auth);
      addTearDown(authority.dispose);
      authority.invalidate();
      backend.auth.notifyAllSubscribers(CollectAuthEvent.tokenRefreshed);
      expect(authority.capture, throwsA(isA<PrivacyRequestException>()));
      await backend.auth.recoverSession(
        jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      );
      expect(authority.capture().sessionId, privacyNewSid);
    },
  );

  test(
    'expired recovery is rejected before it can replace live memory',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final original = backend.auth.currentSession;
      final expired = privacySession().toJson();
      final parts = (expired['access_token'] as String).split('.');
      final claims = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map,
      );
      claims['exp'] = 1516239022;
      parts[1] = base64Url
          .encode(utf8.encode(jsonEncode(claims)))
          .replaceAll('=', '');
      expired['access_token'] = parts.join('.');
      expect(
        () => backend.auth.recoverSession(jsonEncode(expired)),
        throwsA(isA<CollectAuthException>()),
      );
      expect(backend.auth.currentSession, same(original));
    },
  );

  test(
    'disposed authority cannot adopt a late verification response',
    () async {
      final backend = client();
      addTearDown(backend.dispose);
      await backend.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(backend.auth);
      final original = authority.capture();
      await authority.dispose();
      expect(
        () => authority.adopt(original, privacySession(sid: privacyNewSid)),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(backend.auth.currentSession!.user.id, privacySubject);
    },
  );
}
