import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_logout_intent_storage_web.dart'
    as browser_storage;
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

void main() {
  test(
    'browser storage retains an unconfirmed logout across controllers',
    () async {
      const sessionId = '00000000-0000-4000-8000-000000000019';
      const origin = 'https://admin.synthetic.example.invalid';
      final fingerprint = sha256
          .convert(utf8.encode('collect.admin.logout.v1:$sessionId'))
          .toString();
      final storage = browser_storage.createAdminLogoutIntentStorage();
      storage.remove(fingerprint);
      addTearDown(() => storage.remove(fingerprint));
      var signedIn = true;
      var offline = true;
      var logoutRequests = 0;
      final csrf = 'a' * 64;

      Future<http.Response> handle(http.Request request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/session')) {
          return http.Response(
            jsonEncode({
              'user': signedIn
                  ? {
                      'id': '00000000-0000-4000-8000-000000000020',
                      'principalId': '00000000-0000-4000-8000-000000000021',
                      'email': 'synthetic@example.invalid',
                      'role': 'staff',
                      'sessionId': sessionId,
                      'permissions': ['overview.read'],
                      'assuranceLevel': 1,
                      'mfaAt': null,
                      'financialModel': 'canonical_evidence_ledger',
                    }
                  : null,
              'expiresAt': signedIn
                  ? DateTime.now()
                        .toUtc()
                        .add(const Duration(hours: 1))
                        .toIso8601String()
                  : null,
              'ownerEmail': 'owner@example.invalid',
              'csrfToken': signedIn ? csrf : null,
            }),
            200,
          );
        }
        if (path.endsWith('/auth/email-verification')) {
          return http.Response(
            jsonEncode({
              'contractVersion': 1,
              'sessionId': sessionId,
              'emailVerifiedAt': null,
            }),
            200,
          );
        }
        if (path.endsWith('/auth/logout')) {
          logoutRequests++;
          if (offline) throw http.ClientException('Synthetic offline logout');
          expect(request.headers['X-Collect-CSRF'], csrf);
          signedIn = false;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        throw StateError('Unexpected synthetic request');
      }

      CloudflareAdminSession client() => CloudflareAdminSession(
        MockClient(handle),
        origin: Uri.parse(origin),
        environment: fixtures.environment(api: origin, admin: origin),
      );

      final first = client();
      await first.refresh();
      await expectLater(first.signOut(), throwsA(isA<AdminAccountException>()));
      first.dispose();
      expect(storage.readPending(), contains(fingerprint));

      final reopened = client();
      addTearDown(reopened.dispose);
      await reopened.refresh();
      expect(reopened.user, isNull);
      expect(reopened.logoutUnconfirmed, isTrue);
      offline = false;
      await reopened.signOut();
      expect(signedIn, isFalse);
      expect(reopened.logoutUnconfirmed, isFalse);
      expect(storage.readPending(), isNot(contains(fingerprint)));
      expect(logoutRequests, 2);
    },
  );
}
