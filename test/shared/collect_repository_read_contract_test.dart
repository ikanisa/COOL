import 'dart:convert';

import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final payload in [
    null,
    <String, Object>{'unexpected': true},
  ]) {
    test(
      'member catalogue uses scoped RPC and fails closed on $payload',
      () async {
        final paths = <String>[];
        final client = SupabaseClient(
          'http://127.0.0.1:1',
          'local-test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path.endsWith('/get_current_member_profile')) {
              return http.Response(
                jsonEncode({
                  'id': '10000000-0000-0000-0000-000000000001',
                  'public_id': '123456',
                  'whatsapp_phone': '250788123456',
                  'country_code': 'RW',
                  'currency_code': 'RWF',
                }),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(
              request.url.path,
              '/rest/v1/rpc/list_current_user_collections',
            );
            expect(jsonDecode(request.body), isEmpty);
            return http.Response(
              jsonEncode(payload),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'local-test-access',
            'refresh_token': 'local-test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': '10000000-0000-0000-0000-000000000001',
              'aud': 'authenticated',
              'app_metadata': <String, Object>{},
              'user_metadata': <String, Object>{},
              'created_at': '2026-09-02T00:00:00Z',
            },
          }),
        );
        final repository = CollectRepository(supabase: client);
        addTearDown(repository.dispose);
        await repository.loadInitial();
        expect(paths, [
          '/rest/v1/rpc/get_current_member_profile',
          '/rest/v1/rpc/list_current_user_collections',
        ], reason: repository.state.lastError);
        expect(repository.state.hasInitialLoadFailure, isTrue);
        expect(
          repository.state.lastError,
          contains('Group response is unavailable'),
        );
      },
    );
  }
}
