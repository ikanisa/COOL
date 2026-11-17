import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;
import '../core/supabase_google_auth_test.dart' as google;

const _origin = 'https://admin.protected-owner.example.invalid';
const _id = 'owner-opaque-id';
const _principal = 'principal-opaque-id';
const _email = 'configured.owner@example.invalid';
const _publicSession = 'session-public-id';

class _Server {
  bool signedIn = true;
  int loginCalls = 0;
  int sessionReads = 0;
  String role = 'owner';
  String id = _id, principal = _principal, email = _email;
  String? reportedOwnerEmail = _email;
  Object? identity = {
    'schemaVersion': 1,
    'adminId': _id,
    'principalId': _principal,
    'email': _email,
  };
  bool includeIdentity = true;
  bool fresh = true;
  final headers = <String?>[];
  final permissions = <String>['admin_users.manage', 'admin_users.read'];

  Map<String, Object?> envelope() => {
    'user': signedIn
        ? {
            'id': id,
            'principalId': principal,
            'email': email,
            'role': role,
            'sessionId': _publicSession,
            'permissions': permissions,
            'assuranceLevel': 1,
            'mfaAt': null,
            'financialModel': 'canonical_evidence_ledger',
          }
        : null,
    'expiresAt': signedIn
        ? DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 30))
              .toIso8601String()
        : null,
    'ownerEmail': signedIn ? reportedOwnerEmail : 'info@ikanisa.com',
    'csrfToken': signedIn ? 'a' * 64 : null,
    if (signedIn && includeIdentity) 'ownerIdentity': identity,
  };

  http.Response json(Object body) => http.Response(jsonEncode(body), 200);
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/auth/session')) {
      sessionReads++;
      headers.add(request.headers['X-Collect-Owner-Identity-Version']);
      return json(envelope());
    }
    if (request.url.path.endsWith('/auth/email-verification')) {
      return json({
        'contractVersion': 1,
        'sessionId': _publicSession,
        'emailVerifiedAt': fresh
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      });
    }
    if (request.url.path.endsWith('/auth/login')) {
      loginCalls++;
      return json({'ok': true});
    }
    if (request.url.path.endsWith('/auth/otp')) {
      return json({
        'challenge_id': 'synthetic_challenge',
        'retry_after': 60,
        'expires_in': 1800,
      });
    }
    if (request.url.path.endsWith('/auth/verify')) {
      final result = envelope();
      // A login response is never the source of owner authority.
      result['ownerIdentity'] = {
        'schemaVersion': 1,
        'adminId': 'forged',
        'principalId': _principal,
        'email': _email,
      };
      return json(result);
    }
    if (request.url.path.endsWith('/team')) {
      return json({
        'currentEmail': email,
        'canManage': true,
        'members': [],
        'permissionsByRole': {},
      });
    }
    throw StateError('Unexpected synthetic request');
  }

  CloudflareAdminSession client({bool enabled = true}) =>
      CloudflareAdminSession(
        MockClient(handle),
        origin: Uri.parse(_origin),
        environment: fixtures.environment(api: _origin, admin: _origin),
        protectedOwnerEnabled: enabled,
      );
}

void main() {
  test(
    'dynamic configured owner is bound to the authenticated session',
    () async {
      final server = _Server();
      final session = server.client();
      addTearDown(session.dispose);
      await session.refresh();
      expect(server.headers, ['1']);
      expect(session.user?.isCurrentOwner, isTrue);
      final api = CloudflareAdminAccountApi(session);
      expect(api.invitationManagementAuthorized, isTrue);
      expect(
        api.isProtectedOwnerTarget(
          adminId: _id,
          email: 'misleading@example.invalid',
        ),
        isTrue,
      );
      expect(
        api.isProtectedOwnerTarget(adminId: 'other', email: _email),
        isTrue,
      );
      expect(
        api.isProtectedOwnerTarget(
          adminId: 'other',
          email: 'staff@example.invalid',
        ),
        isFalse,
      );
    },
  );

  test(
    'missing or inconsistent proof preserves login but closes owner actions',
    () async {
      final cases = <void Function(_Server)>[
        (s) => s.includeIdentity = false,
        (s) => s.identity = null,
        (s) => s.identity = {
          'schemaVersion': 2,
          'adminId': _id,
          'principalId': _principal,
          'email': _email,
        },
        (s) => s.identity = {
          'schemaVersion': 1.0,
          'adminId': _id,
          'principalId': _principal,
          'email': _email,
        },
        (s) => s.identity = {
          'schemaVersion': 1,
          'adminId': 'invalid\nowner',
          'principalId': _principal,
          'email': _email,
        },
        (s) => s.identity = {
          'schemaVersion': 1,
          'adminId': _id,
          'principalId': _principal,
          'email': _email,
          'unexpected': true,
        },
        (s) => s.identity = {
          'schemaVersion': 1,
          'adminId': 'other',
          'principalId': _principal,
          'email': _email,
        },
        (s) => s.identity = {
          'schemaVersion': 1,
          'adminId': _id,
          'principalId': 'other',
          'email': _email,
        },
        (s) => s.identity = {
          'schemaVersion': 1,
          'adminId': _id,
          'principalId': _principal,
          'email': 'other@example.invalid',
        },
        (s) => s.reportedOwnerEmail = null,
        (s) => s.email = ' CONFIGURED.OWNER@EXAMPLE.INVALID ',
        (s) => s.role = 'staff',
        (s) => s.permissions.remove('admin_users.manage'),
        (s) => s.fresh = false,
      ];
      for (final change in cases) {
        final server = _Server();
        change(server);
        final session = server.client();
        await session.refresh();
        expect(session.user, isNotNull);
        expect(await session.recheckSession(), isTrue);
        expect(
          CloudflareAdminAccountApi(session).invitationManagementAuthorized,
          isFalse,
        );
        session.dispose();
      }
    },
  );

  test(
    'missing owner proof closes team controls even if a legacy server says canManage',
    () async {
      final server = _Server()
        ..identity = null
        ..reportedOwnerEmail = null;
      final session = server.client();
      addTearDown(session.dispose);
      await session.refresh();
      final api = CloudflareAdminAccountApi(session);
      expect((await api.loadTeam()).canManage, isFalse);
      expect(
        () => api.revokeMember('other-account'),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );

  test('signed-out and legacy server envelopes remain usable', () async {
    final signedOut = _Server()..signedIn = false;
    final client = signedOut.client();
    expect(await client.recheckSession(), isFalse);
    expect(client.user, isNull);
    client.dispose();

    final legacy = _Server()
      ..id = '00000000-0000-4000-8000-000000000001'
      ..principal = fixtures.principal
      ..email = 'info@ikanisa.com'
      ..reportedOwnerEmail = 'info@ikanisa.com'
      ..includeIdentity = false;
    final oldClient = legacy.client(enabled: false);
    await oldClient.refresh();
    expect(legacy.headers.single, isNull);
    expect(oldClient.user?.isCurrentOwner, isTrue);
    expect(
      CloudflareAdminAccountApi(oldClient).invitationManagementAuthorized,
      isTrue,
    );
    oldClient.dispose();
  });

  test(
    'reopening a saved session does not require login and owner changes fence work',
    () async {
      final server = _Server();
      final original = server.client();
      await original.refresh();
      final fence = original.authorityFence;
      original.dispose();
      final reopened = server.client();
      addTearDown(reopened.dispose);
      await reopened.refresh();
      expect(reopened.user?.isCurrentOwner, isTrue);
      expect(server.loginCalls, 0);
      expect(server.sessionReads, 2);
      final before = reopened.authorityFence;
      expect(before.key, fence.key);
      server.identity = {
        'schemaVersion': 1,
        'adminId': 'new-owner',
        'principalId': 'new-principal',
        'email': 'new.owner@example.invalid',
      };
      server.reportedOwnerEmail = 'new.owner@example.invalid';
      await reopened.refresh();
      expect(reopened.user, isNotNull);
      expect(reopened.user?.isCurrentOwner, isFalse);
      expect(reopened.authorityFence, isNot(before));
    },
  );

  test(
    'password and email OTP sign-in obtain owner proof from the session read',
    () async {
      final server = _Server();
      final password = server.client();
      await password.signIn(_email, 'synthetic-password');
      expect(password.user?.isCurrentOwner, isTrue);
      expect(server.loginCalls, 1);
      password.dispose();

      final otp = server.client();
      addTearDown(otp.dispose);
      final receipt = await otp.requestEmailOtp(_email);
      await otp.verifyEmailOtp(
        email: _email,
        challengeId: receipt.challengeId,
        code: '123456',
      );
      expect(otp.user?.isCurrentOwner, isTrue);
      expect(otp.user?.ownerIdentity?.adminId, _id);
    },
  );

  test(
    'Google exchange compares session identity before adding owner proof',
    () async {
      final server = _Server();
      const googleOrigin = 'https://platform-admin.collect.ikanisa.com';
      late String clientState;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/google/start')) {
            final body = jsonDecode(request.body) as Map;
            clientState = body['client_state'] as String;
            final url = google.authorizeUrl(
              redirect:
                  '$googleOrigin/functions/v1/collect-api/v1/auth/google/callback?state=${'a' * 43}',
            );
            return server.json({'authorization_url': url.toString()});
          }
          if (request.url.path.endsWith('/google/exchange')) {
            final response = server.envelope()..remove('ownerIdentity');
            return server.json(response);
          }
          return server.handle(request);
        }),
        origin: Uri.parse(googleOrigin),
        googleAuthEnabled: true,
        environment: fixtures.environment(
          api: googleOrigin,
          admin: googleOrigin,
        ),
        protectedOwnerEnabled: true,
      );
      addTearDown(session.dispose);
      await session.signInWithGoogle(
        authorize: (createUrl, state, callbackOrigin) async {
          await createUrl(googleOrigin);
          expect(state, clientState);
          return {'code': 'c' * 43, 'state': state};
        },
      );
      expect(session.user?.isCurrentOwner, isTrue);
      expect(session.user?.ownerIdentity?.adminId, _id);
    },
  );
}
