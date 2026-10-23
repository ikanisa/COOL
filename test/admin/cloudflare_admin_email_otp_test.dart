import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _email = 'teammate@collect.example';
const _challenge = 'email-challenge-one';
Map<String, dynamic> _receipt() => {
  'accepted': true,
  'challenge_id': _challenge,
  'retry_after': 60,
  'expires_in': 300,
  'emailStatus': 'accepted',
};
Map<String, dynamic> _session({String email = _email}) => {
  'user': {
    'id': '00000000-0000-4000-8000-000000000001',
    'email': email,
    'role': 'owner',
    'sessionId': 'public-session-one',
    'assuranceLevel': 1,
    'permissions': ['overview.read', 'admin_users.manage'],
  },
  'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
};
http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
CloudflareAdminSession _client(
  FutureOr<http.Response> Function(http.Request) handler,
) => CloudflareAdminSession(
  MockClient((request) async => handler(request)),
  origin: Uri.parse('https://admin.collect.example'),
  environment: legacyBackendFixtureEnvironment,
);

void main() {
  test(
    'approved email uses Admin cookie endpoints and retains owner MFA requirement',
    () async {
      final requests = <http.Request>[];
      final client = _client((request) {
        requests.add(request);
        return request.url.path.endsWith('/auth/otp')
            ? _json(_receipt(), 202)
            : _json(_session());
      });
      addTearDown(client.dispose);
      final api = CloudflareAdminAccountApi(client);
      final receipt = await api.requestEmailOtp(' Teammate@Collect.Example ');
      expect(client.user, isNull);
      await api.verifyEmailOtp(
        email: _email,
        challengeId: receipt.challengeId,
        code: '123456',
      );
      expect(requests.map((request) => request.url.path), [
        '/api/admin/auth/otp',
        '/api/admin/auth/verify',
        '/api/admin/auth/session',
      ]);
      expect(jsonDecode(requests.first.body), {'email': _email});
      expect(jsonDecode(requests[1].body), {
        'email': _email,
        'challenge_id': _challenge,
        'code': '123456',
      });
      expect(
        requests.every(
          (request) => !request.headers.containsKey('Authorization'),
        ),
        isTrue,
      );
      expect(client.user?.email, _email);
      expect(client.user?.assuranceLevel, 1);
      expect(client.user?.mfaAt, isNull);
    },
  );

  test(
    'unapproved email maps to access exception and has no session',
    () async {
      final client = _client(
        (_) => _json({
          'error': {'code': 'admin_access_not_approved'},
        }, 403),
      );
      addTearDown(client.dispose);
      final api = CloudflareAdminAccountApi(client);
      await expectLater(
        api.requestEmailOtp(_email),
        throwsA(isA<AdminAccountAccessNotApproved>()),
      );
      expect(client.user, isNull);
    },
  );

  test(
    'invalid code retains same challenge for correction and never installs session',
    () async {
      var verifies = 0;
      final client = _client((request) {
        if (request.url.path.endsWith('/auth/otp')) {
          return _json(_receipt(), 202);
        }
        verifies++;
        return verifies == 1
            ? _json({
                'error': {'code': 'invalid_credentials'},
              }, 401)
            : _json(_session());
      });
      addTearDown(client.dispose);
      final receipt = await client.requestEmailOtp(_email);
      await expectLater(
        client.verifyEmailOtp(
          email: _email,
          challengeId: receipt.challengeId,
          code: '000000',
        ),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (error) => error.message,
            'recovery',
            contains('invalid or expired'),
          ),
        ),
      );
      expect(client.user, isNull);
      await client.verifyEmailOtp(
        email: _email,
        challengeId: receipt.challengeId,
        code: '123456',
      );
      expect(client.user?.email, _email);
    },
  );

  test(
    'changed email, challenge or malformed code never dispatches verification',
    () async {
      var requests = 0;
      final client = _client((_) {
        requests++;
        return _json(_receipt(), 202);
      });
      addTearDown(client.dispose);
      await client.requestEmailOtp(_email);
      for (final identity in [
        (
          email: 'different@collect.example',
          challenge: _challenge,
          code: '123456',
        ),
        (email: _email, challenge: 'different-challenge', code: '123456'),
        (email: _email, challenge: _challenge, code: '123'),
      ]) {
        await expectLater(
          client.verifyEmailOtp(
            email: identity.email,
            challengeId: identity.challenge,
            code: identity.code,
          ),
          throwsA(anyOf(isA<AdminAccountException>(), isA<FormatException>())),
        );
      }
      expect(requests, 1);
    },
  );

  test(
    'unknown delivery preserves challenge and sends no automatic retry',
    () async {
      var sends = 0;
      final client = _client((request) {
        if (request.url.path.endsWith('/auth/otp')) {
          sends++;
          final body = _receipt()..remove('emailStatus');
          body['error'] = {'code': 'email_delivery_unknown'};
          return _json(body, 503);
        }
        return _json(_session());
      });
      addTearDown(client.dispose);
      await expectLater(
        client.requestEmailOtp(_email),
        throwsA(
          isA<AdminEmailOtpDeliveryUnknown>().having(
            (error) => error.receipt.challengeId,
            'bound challenge',
            _challenge,
          ),
        ),
      );
      await client.verifyEmailOtp(
        email: _email,
        challengeId: _challenge,
        code: '123456',
      );
      expect(client.user?.email, _email);
      expect(sends, 1);
    },
  );

  for (final mode in ['lost reply', 'malformed success']) {
    test(
      '$mode reconciles HttpOnly session once without replaying code',
      () async {
        var verifies = 0;
        var reads = 0;
        final client = _client((request) {
          if (request.url.path.endsWith('/auth/otp')) {
            return _json(_receipt(), 202);
          }
          if (request.url.path.endsWith('/auth/verify')) {
            verifies++;
            if (mode == 'lost reply') throw http.ClientException('lost');
            return http.Response('<html>proxy</html>', 200);
          }
          reads++;
          return _json(_session());
        });
        addTearDown(client.dispose);
        await client.requestEmailOtp(_email);
        await client.verifyEmailOtp(
          email: _email,
          challengeId: _challenge,
          code: '123456',
        );
        expect(verifies, 1);
        expect(reads, 1);
        expect(client.user?.email, _email);
      },
    );
  }

  test('unknown verification cannot recover another email cookie', () async {
    final client = _client((request) {
      if (request.url.path.endsWith('/auth/otp')) return _json(_receipt(), 202);
      if (request.url.path.endsWith('/auth/verify')) {
        throw http.ClientException('lost');
      }
      return _json(_session(email: 'different@collect.example'));
    });
    addTearDown(client.dispose);
    await client.requestEmailOtp(_email);
    await expectLater(
      client.verifyEmailOtp(
        email: _email,
        challengeId: _challenge,
        code: '123456',
      ),
      throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
    );
    expect(client.user, isNull);
  });

  test('sign-out fences late OTP request response', () async {
    final pending = Completer<http.Response>();
    final client = _client((_) => pending.future);
    addTearDown(client.dispose);
    final request = client.requestEmailOtp(_email);
    final rejection = expectLater(
      request,
      throwsA(isA<AdminAccountException>()),
    );
    await Future<void>.delayed(Duration.zero);
    client.clear();
    pending.complete(_json(_receipt(), 202));
    await rejection;
    expect(client.user, isNull);
  });

  test('invalid cooldown receipt never permits OTP verification', () async {
    var requests = 0;
    final client = _client((_) {
      requests++;
      return _json({..._receipt(), 'retry_after': 0}, 202);
    });
    addTearDown(client.dispose);
    await expectLater(
      client.requestEmailOtp(_email),
      throwsA(isA<AdminAccountException>()),
    );
    await expectLater(
      client.verifyEmailOtp(
        email: _email,
        challengeId: _challenge,
        code: '123456',
      ),
      throwsA(isA<AdminAccountException>()),
    );
    expect(requests, 1);
  });
}
