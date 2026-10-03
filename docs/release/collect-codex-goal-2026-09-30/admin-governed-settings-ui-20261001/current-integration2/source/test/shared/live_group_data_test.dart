import 'dart:convert';

import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unconfigured live repository never creates sample groups', () async {
    final repository = CollectRepository();
    addTearDown(repository.dispose);

    await repository.loadInitial();

    expect(repository.state.currentProfile, isNull);
    expect(repository.state.collections, isEmpty);
    expect(repository.state.paymentIntents, isEmpty);
    expect(repository.state.contributions, isEmpty);
  });

  for (final status in [200, 403]) {
    test(
      'empty or denied directory ($status) never falls back to samples',
      () async {
        final client = _client(
          (_) => http.Response(
            jsonEncode(
              status == 200 ? [] : {'message': 'Directory unavailable'},
            ),
            status,
          ),
        );
        final repository = CollectRepository(supabase: client);
        addTearDown(client.dispose);
        addTearDown(repository.dispose);

        await repository.loadInitial();

        expect(repository.state.collections, isEmpty);
        expect(repository.state.currentProfile, isNull);
        expect(repository.state.paymentIntents, isEmpty);
        expect(repository.state.contributions, isEmpty);
        expect(repository.state.lastError, status == 200 ? isNull : isNotNull);
      },
    );
  }

  test(
    'directory additions, renames and removal follow backend rows exactly',
    () async {
      var rows = <Map<String, Object>>[
        {
          'id': 'remote-group-id',
          'slug': 'remote-group-slug',
          'title': 'Backend-provided title',
          'collection_type': 'ikimina',
          'is_public': true,
          'created_at': '2026-09-04T00:00:00Z',
        },
      ];
      final client = _client((request) {
        expect(request.url.path, '/rest/v1/public_collections_view');
        return http.Response(jsonEncode(rows), 200);
      });
      final repository = CollectRepository(supabase: client);
      addTearDown(client.dispose);
      addTearDown(repository.dispose);

      await repository.loadInitial();
      expect(repository.state.collections.single.id, 'remote-group-id');
      expect(
        repository.state.collections.single.title,
        'Backend-provided title',
      );

      rows.single['title'] = 'Updated backend title';
      await repository.loadInitial();
      expect(
        repository.state.collections.single.title,
        'Updated backend title',
      );

      rows = [];
      await repository.loadInitial();
      expect(repository.state.collections, isEmpty);
    },
  );
}

SupabaseClient _client(http.Response Function(http.Request) handler) =>
    SupabaseClient(
      'http://127.0.0.1:1',
      'local-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final response = handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
