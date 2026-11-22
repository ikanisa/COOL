import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _BrokenStorage implements CollectAuthSessionStorage {
  @override
  Future<String?> read() async => throw StateError('PRIVATE-SESSION-RECEIPT');
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _NoNetwork extends http.BaseClient {
  int requests = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Network is forbidden in this test');
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'failed local initializer is disposed before an independent retry',
    () async {
      final failedNetwork = _NoNetwork();
      final partial = CollectCloudflareClient(
        'https://startup-fixture.invalid',
        httpClient: failedNetwork,
        sessionStorage: _BrokenStorage(),
      );
      await expectLater(partial.initialize(), throwsStateError);
      await partial.dispose();
      expect(failedNetwork.closed, isTrue);
      expect(failedNetwork.requests, 0);
      final retryNetwork = _NoNetwork();
      final retry = CollectCloudflareClient(
        'https://startup-fixture.invalid',
        httpClient: retryNetwork,
        sessionStorage: CollectMemorySessionStorage(),
      );
      addTearDown(retry.dispose);
      await retry.initialize();
      expect(retry.auth.currentSession, isNull);
      expect(retryNetwork.requests, 0);
      expect(retry.auth, isNot(same(partial.auth)));
    },
  );
}
