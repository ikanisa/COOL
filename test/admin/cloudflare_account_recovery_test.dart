import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

void main() {
  for (final response in ['lost', '503', 'malformed success']) {
    test(
      'password setup $response requires sign-in recovery without replay',
      () async {
        var mutations = 0;
        final session = CloudflareAdminSession(
          MockClient((request) async {
            mutations++;
            if (response == 'lost') throw http.ClientException('Lost response');
            return http.Response(
              response == '503'
                  ? jsonEncode({
                      'error': {'code': 'service_unavailable'},
                    })
                  : '<html>proxy</html>',
              response == '503' ? 503 : 200,
            );
          }),
          origin: Uri.parse('https://admin.example.test'),
          environment: legacyBackendFixtureEnvironment,
        );
        final api = CloudflareAdminAccountApi(session);
        await expectLater(
          api.completePasswordSetup(
            'one-use-token',
            'chosen-new-password',
            invite: true,
          ),
          throwsA(
            isA<AdminAccountSecurityOutcomeUnknown>().having(
              (error) => error.message,
              'recovery',
              contains('Sign in with the password you just chose'),
            ),
          ),
        );
        expect(mutations, 1);
        session.dispose();
      },
    );
  }

  test('rejected expired link remains a known rejection', () async {
    final session = CloudflareAdminSession(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'invalid_link'},
          }),
          400,
        ),
      ),
      origin: Uri.parse('https://admin.example.test'),
      environment: legacyBackendFixtureEnvironment,
    );
    final api = CloudflareAdminAccountApi(session);
    await expectLater(
      api.completePasswordSetup(
        'expired-token',
        'chosen-new-password',
        invite: false,
      ),
      throwsA(
        isA<CloudflareAdminRequestException>().having(
          (error) => error.outcomeUnknown,
          'known response',
          false,
        ),
      ),
    );
    session.dispose();
  });
}
