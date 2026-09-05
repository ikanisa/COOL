import '../fixtures/collect_repository_fixture.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _receipt = {
  'collection_id': 'qa-private-group',
  'public_id': '123456',
  'role': 'admin',
  'status': 'active',
};

Future<SupabaseClient> _client(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'http://127.0.0.1:1',
    'local-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response(
        response.body,
        response.statusCode,
        headers: {'content-type': 'application/json', ...response.headers},
        request: request,
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
        'id': 'local-user',
        'aud': 'authenticated',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-09-02T00:00:00Z',
      },
    }),
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'live grant requires exact receipt and invalidates server roster',
    () async {
      var grants = 0;
      var rosterReads = 0;
      final client = await _client((request) async {
        if (request.url.path.endsWith('/add_group_admin')) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'collection': 'qa-private-group',
            'member_public_id': '123456',
          });
          grants++;
          return http.Response(jsonEncode(_receipt), 200);
        }
        expect(
          request.url.path,
          '/rest/v1/rpc/list_current_member_group_roster',
        );
        rosterReads++;
        return http.Response(
          jsonEncode([
            {
              'public_id': '123456',
              'role': grants == 0 ? 'member' : 'admin',
              'status': 'active',
              'joined_at': '2026-08-01T00:00:00Z',
              'amount_scope': 'hidden',
              'contributions': [],
            },
          ]),
          200,
        );
      });
      final repo = FixtureCollectRepository(supabase: client);
      addTearDown(repo.dispose);
      final before = repo.state;
      expect(
        (await repo.membersForCollection('qa-private-group')).single.role,
        'member',
      );
      await repo.inviteCollectionAdmin(
        collectionId: 'qa-private-group',
        publicId: ' 123456 ',
      );
      expect(
        (await repo.membersForCollection('qa-private-group')).single.role,
        'admin',
      );
      expect(grants, 1);
      expect(rosterReads, 2);
      expect(identical(before.collections, repo.state.collections), isFalse);
      expect(before.collections, repo.state.collections);
      expect(before.currentProfile, same(repo.state.currentProfile));
      expect(before.contributions, same(repo.state.contributions));
    },
  );

  final badReceipts = <Object?>[
    null,
    {},
    [],
    true,
    {..._receipt, 'collection_id': 'another-group'},
    {..._receipt, 'public_id': '654321'},
    {..._receipt, 'role': 'owner'},
    {..._receipt, 'status': 'invited'},
    {..._receipt, 'name': 'Must not leak'},
  ];
  for (var index = 0; index < badReceipts.length; index++) {
    test(
      'live grant rejects unverified response $index without optimistic changes',
      () async {
        final client = await _client(
          (_) async => http.Response(jsonEncode(badReceipts[index]), 200),
        );
        final repo = FixtureCollectRepository(supabase: client);
        addTearDown(repo.dispose);
        final before = repo.state;
        await expectLater(
          repo.inviteCollectionAdmin(
            collectionId: 'qa-private-group',
            publicId: '123456',
          ),
          throwsFormatException,
        );
        expect(repo.state, same(before));
      },
    );
  }

  for (final code in ['22023', '42501', 'PGRST202']) {
    test('live API $code failure is not group admin success', () async {
      final client = await _client(
        (_) async => http.Response(
          jsonEncode({
            'code': code,
            'message': 'Server-only details',
            'details': null,
            'hint': null,
          }),
          code == '42501' ? 403 : 400,
        ),
      );
      final repo = FixtureCollectRepository(supabase: client);
      addTearDown(repo.dispose);
      final before = repo.state;
      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        code == '22023'
            ? throwsFormatException
            : code == '42501'
            ? throwsStateError
            : throwsA(isA<PostgrestException>()),
      );
      expect(repo.state, same(before));
    });
  }

  test(
    'sign-out while grant is pending cannot publish success to another session',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final client = await _client((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        started.complete();
        return response.future;
      });
      final repo = FixtureCollectRepository(supabase: client);
      addTearDown(repo.dispose);
      final before = repo.state;
      final pending = repo.inviteCollectionAdmin(
        collectionId: 'qa-private-group',
        publicId: '123456',
      );
      final assertion = expectLater(pending, throwsStateError);
      await started.future;
      await client.auth.signOut(scope: SignOutScope.local);
      response.complete(http.Response(jsonEncode(_receipt), 200));
      await assertion;
      expect(repo.state, same(before));
    },
  );
}
