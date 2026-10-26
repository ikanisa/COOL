// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';

import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'privacy_test_support.dart';

void main() {
  test(
    'actual Auth UID changes recreate provider while same-owner OTP SID keeps its controller',
    () async {
      final client = CollectCloudflareClient(
        'https://synthetic.invalid',
        httpClient: MockClient(
          (r) async => r.url.path.endsWith('/logout')
              ? http.Response('{"ok":true}', 200)
              : throw StateError('No real Auth HTTP allowed'),
        ),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(privacySession().toJson()));
      final transport = CollectPrivacyRequestTransport(
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/otp')) {
            return http.Response(
              '{"challenge_id":"synthetic-privacy-challenge"}',
              200,
            );
          }
          if (r.url.path.endsWith('/verify')) {
            return http.Response(
              jsonEncode(privacySession(sid: privacyNewSid).toJson()),
              200,
            );
          }
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(
              privacyReceiptJson(
                submission: true,
                submissionId: body['p_request_id'] as String,
                requestId: body['p_request_id'] as String,
              ),
            ),
            200,
          );
        }),
        apiUrl: 'https://synthetic.invalid',
      );
      final container = ProviderContainer(
        overrides: [
          collectBackendClientProvider.overrideWithValue(client),
          privacyRequestTransportProvider.overrideWithValue(transport),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen<PrivacyRequestController?>(
        privacyRequestControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      final first = container.read(privacyRequestControllerProvider)!;
      await first.sendCode();
      await first.verifyCode('123456');
      await container.pump();
      expect(container.read(privacyRequestControllerProvider), same(first));
      await first.submit(reason: 'reason');
      expect(first.receipt, isNotNull);
      final switching = client.auth.recoverSession(
        jsonEncode(privacySession(subject: privacyOtherSubject).toJson()),
      );
      // The synchronous owner fence works before async Provider delivery.
      expect(first.receipt, isNull);
      expect(first.pendingIdentity, isNull);
      await switching;
      await container.pump();
      final second = container.read(privacyRequestControllerProvider)!;
      expect(second, isNot(same(first)));
      await expectLater(
        first.refreshStatus(),
        throwsA(isA<PrivacyRequestException>()),
      );
      container.read(privacySessionAuthorityProvider)!.invalidate();
      await client.auth.signOut(scope: CollectSignOutScope.local);
      await container.pump();
      expect(container.read(privacyRequestControllerProvider), isNull);
      await expectLater(
        second.sendCode(),
        throwsA(isA<PrivacyRequestException>()),
      );
    },
  );
  test(
    'captured view subject cannot begin a request for a different live Auth owner',
    () async {
      final auth = CollectCloudflareClient('https://synthetic.invalid').auth;
      addTearDown(auth.dispose);
      await auth.recoverSession(jsonEncode(privacySession().toJson()));
      final authority = CollectPrivacySessionAuthority(auth);
      addTearDown(authority.dispose);
      var calls = 0;
      final controller = PrivacyRequestController(
        authority: authority,
        subjectId: privacyOtherSubject,
        transport: CollectPrivacyRequestTransport(
          httpClient: MockClient((_) async {
            ++calls;
            return http.Response('{}', 200);
          }),
          apiUrl: 'https://synthetic.invalid',
        ),
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.sendCode(),
        throwsA(
          isA<PrivacyRequestException>().having(
            (e) => e.failure,
            'fixed denial',
            PrivacyFailure.sessionChanged,
          ),
        ),
      );
      expect(calls, 0);
    },
  );
}
