import 'dart:async';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'privacy_test_support.dart';

class AbortObservingClient extends http.BaseClient {
  bool observedAbort = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request, isA<http.AbortableRequest>());
    await (request as http.AbortableRequest).abortTrigger;
    observedAbort = true;
    throw http.RequestAbortedException(request.url);
  }
}

class ChunkedOversizeClient extends http.BaseClient {
  bool cancelled = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    controller.add(List.filled(32768, 120));
    controller.add(List.filled(32769, 120));
    unawaited(controller.close());
    return http.StreamedResponse(controller.stream, 200);
  }
}

void main() {
  test(
    'HTTP deadline signals actual abortable request, with a fixed safe error',
    () async {
      final client = AbortObservingClient();
      addTearDown(client.close);
      final transport = SupabasePrivacyRequestTransport(
        httpClient: client,
        supabaseUrl: 'https://synthetic.invalid',
        publishableKey: 'SYNTHETIC_PUBLIC_KEY',
        timeout: const Duration(milliseconds: 10),
      );
      final frame = PrivacySessionSnapshot.parse(privacySession(), 0)!;
      await expectLater(
        transport.sendCode(frame),
        throwsA(
          isA<PrivacyRequestException>().having(
            (e) => e.failure,
            'fixed failure',
            PrivacyFailure.verificationUnavailable,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.observedAbort, isTrue);
    },
  );
  test(
    'unknown-length oversized response is cancelled and cannot confirm a write',
    () async {
      final client = ChunkedOversizeClient();
      addTearDown(client.close);
      final transport = SupabasePrivacyRequestTransport(
        httpClient: client,
        supabaseUrl: 'https://synthetic.invalid',
        publishableKey: 'SYNTHETIC_PUBLIC_KEY',
      );
      await expectLater(
        transport.submit(
          PrivacySessionSnapshot.parse(privacySession(), 0)!,
          privacySubmission,
          'reason',
        ),
        throwsA(
          isA<PrivacyRequestException>().having(
            (e) => e.failure,
            'fixed failure',
            PrivacyFailure.outcomeUnknown,
          ),
        ),
      );
      expect(client.cancelled, isTrue);
    },
  );
}
