import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/synthetic_jwt.dart';

const _user = '11111111-1111-4111-8111-111111111111';
const _group = '22222222-2222-4222-8222-222222222222';
const _sessionA = '33333333-3333-4333-8333-333333333333';
const _sessionB = '44444444-4444-4444-8444-444444444444';

String _session(String session) => jsonEncode({
  'access_token': syntheticJwt(
    {'alg': 'HS256', 'typ': 'JWT'},
    {
      'sub': _user,
      'session_id': session,
      'role': 'authenticated',
      'surface': 'member',
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    },
  ),
  'refresh_token': 'synthetic-$session',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': _user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
  },
});

CollectState _state() => CollectState(
  currentProfile: const CollectProfile(
    id: _user,
    publicId: '038491',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [
    CollectCollection(
      id: _group,
      slug: 'public-synthetic-group',
      creatorUserId: 'platform',
      title: 'Synthetic public group',
      description: '',
      receiverNetwork: 'mtn_momo',
      primaryPaymentRail: 'rwanda_momo',
      isPublic: true,
      createdAt: DateTime.utc(2026),
    ),
  ],
  paymentIntents: const [],
  contributions: const [],
);

Map<String, Object?> _serverGroup({bool member = true}) => {
  'id': _group,
  'slug': 'public-synthetic-group',
  'creator_user_id': 'platform',
  'title': 'Synthetic public group',
  'description': '',
  'collection_type': 'ikimina',
  'receiver_network': 'mtn_momo',
  'receiver_momo_number': '250788123456',
  'payment_rail': 'rwanda_momo',
  'visibility_status': 'public_approved',
  'is_public': true,
  'is_member': member,
  'status': 'active',
  'moderation_status': 'not_requested',
  'created_at': '2026-01-01T00:00:00Z',
};

// Isolate the join RPC and hydration from the post-join full refresh. The
// separate discovery test exercises the actual refresh and revocation path.
class _JoinOnlyRepository extends CollectRepository {
  _JoinOnlyRepository(CollectCloudflareClient client)
    : super.fixture(initialState: _state(), backend: client);

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'public join sends group ID and hydrates only confirmed membership',
    () async {
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'http://127.0.0.1:1',
        httpClient: MockClient((request) async {
          requests.add(request);
          final value = request.url.path.endsWith('/join_public_group')
              ? _group
              : [_serverGroup()];
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(_session(_sessionA));
      final repo = _JoinOnlyRepository(client);
      addTearDown(repo.dispose);

      final joined = await repo.joinPublicGroup(_group);
      expect(joined.isCurrentUserMember, isTrue);
      expect(repo.state.collections.single.isCurrentUserMember, isTrue);
      expect(requests.length, 2);
      expect(requests.first.url.path, endsWith('/join_public_group'));
      final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(body['p_collection_id'], _group);
      expect(body['p_request_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(requests.first.headers['authorization'], startsWith('Bearer '));
    },
  );

  test('archived group readback cannot publish join success', () async {
    final requests = <http.Request>[];
    final client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        requests.add(request);
        final value = request.url.path.endsWith('/join_public_group')
            ? _group
            : [
                _serverGroup()
                  ..['status'] = 'archived'
                  ..['moderation_status'] = 'archived',
              ];
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session(_sessionA));
    final repo = _JoinOnlyRepository(client);
    addTearDown(repo.dispose);

    await expectLater(repo.joinPublicGroup(_group), throwsFormatException);
    expect(requests.length, 2);
    expect(requests.last.url.path, endsWith('/list_current_user_collections'));
    expect(repo.state.collections.single.isCurrentUserMember, isFalse);
  });

  test(
    'same-user replacement during join cannot publish stale membership',
    () async {
      final entered = Completer<void>();
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        'http://127.0.0.1:1',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/join_public_group')) {
            entered.complete();
            return pending.future;
          }
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(_session(_sessionA));
      final originalBearer =
          'Bearer ${client.auth.currentSession!.accessToken}';
      final repo = _JoinOnlyRepository(client);
      addTearDown(repo.dispose);

      final result = repo.joinPublicGroup(_group);
      await entered.future;
      await client.auth.recoverSession(_session(_sessionB));
      pending.complete(
        http.Response(
          jsonEncode(_group),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(result, throwsStateError);
      expect(
        requests.where(
          (request) =>
              request.url.path.endsWith('/list_current_user_collections') &&
              request.headers['authorization'] == originalBearer,
        ),
        isEmpty,
      );
      expect(
        repo.state.collections.any(
          (group) => group.id == _group && group.isCurrentUserMember,
        ),
        isFalse,
      );
    },
  );
}
