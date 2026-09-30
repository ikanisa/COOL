import 'dart:async';
import 'dart:convert';

import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _firstUser = '11111111-1111-4111-8111-111111111111';
const _secondUser = '22222222-2222-4222-8222-222222222222';

String _session(String userId) => jsonEncode({
  'access_token': 'synthetic-access-$userId',
  'refresh_token': 'synthetic-refresh-$userId',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-09-28T00:00:00Z',
  },
});

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'http://127.0.0.1:1',
      'local-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'authenticated identity updates after sign-in and account switch',
    () async {
      final client = _client((_) async => http.Response('{}', 200));
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final observed = <String?>[];
      final listener = container.listen(
        collectAuthenticatedUserIdProvider,
        (_, next) => observed.add(next),
        fireImmediately: true,
      );
      addTearDown(listener.close);
      expect(container.read(collectAuthenticatedUserIdProvider), isNull);

      await client.auth.setInitialSession(_session(_firstUser));
      await pumpEventQueue();
      expect(container.read(collectAuthenticatedUserIdProvider), _firstUser);

      await client.auth.setInitialSession(_session(_secondUser));
      await pumpEventQueue();
      expect(container.read(collectAuthenticatedUserIdProvider), _secondUser);
      expect(observed, containsAllInOrder([null, _firstUser, _secondUser]));
    },
  );

  test(
    'a delayed join response cannot publish a previous account group',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      late http.Request joinRequest;
      final client = _client((request) async {
        if (request.url.path.endsWith('/rpc/join_group_by_share_code')) {
          joinRequest = request;
          started.complete();
          return response.future;
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_firstUser));
      final repository = FixtureCollectRepository(
        supabase: client,
        profileOverride: const CollectProfile(
          id: _firstUser,
          publicId: '038491',
          whatsappPhone: '+250788123456',
          countryCode: 'RW',
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
        ),
      );
      addTearDown(repository.dispose);

      final join = repository.joinGroupBySlug('qa-private-group');
      await started.future;
      await client.auth.setInitialSession(_session(_secondUser));
      response.complete(
        http.Response(
          jsonEncode('qa-private-group'),
          200,
          headers: {'content-type': 'application/json'},
          request: joinRequest,
        ),
      );
      await expectLater(join, throwsStateError);
      expect(
        repository.state.collections.any(
          (group) => group.id == 'qa-private-group',
        ),
        isFalse,
      );
    },
  );
}
