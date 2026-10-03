import 'package:collect_app/core/startup/collect_startup_controller.dart';
import 'package:collect_app/core/supabase/collect_supabase_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class _BrokenStorage extends EmptyLocalStorage {
  @override
  Future<void> initialize() async =>
      throw StateError('PRIVATE-SESSION-RECEIPT');
}

class _MemoryPkce extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> removeItem({required String key}) async {}
  @override
  Future<void> setItem({required String key, required String value}) async {}
}

class _NoNetwork extends http.BaseClient {
  var requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Network is forbidden in this test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual failed Supabase storage is disposed before retrying', () async {
    final network = _NoNetwork();
    Supabase? partial;
    Future<Supabase> initialize(LocalStorage storage) async {
      try {
        return await Supabase.initialize(
          url: 'https://startup-fixture.invalid',
          publishableKey: 'synthetic-key',
          debug: false,
          httpClient: network,
          authOptions: FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: storage,
            pkceAsyncStorage: _MemoryPkce(),
          ),
        );
      } catch (_) {
        partial = Supabase.instance;
        expect(partial!.isInitialized, isTrue);
        rethrow;
      }
    }

    try {
      await expectLater(
        initializeCollectSupabase(() => initialize(_BrokenStorage())),
        throwsA(
          isA<CollectStartupFailure>().having(
            (e) => e.retryAllowed,
            'cleanup allows retry',
            isTrue,
          ),
        ),
      );
      expect(partial!.isInitialized, isFalse);
      final client = await initializeCollectSupabase(
        () => initialize(const EmptyLocalStorage()),
      );
      expect(Supabase.instance.isInitialized, isTrue);
      expect(client, same(Supabase.instance.client));
      expect(client.auth.currentSession, isNull);
      expect(network.requests, 0);
    } finally {
      if (partial?.isInitialized ?? false) await partial!.dispose();
    }
  });
}
