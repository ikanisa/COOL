import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _own = <String, Object?>{
  'public_id': '038491',
  'role': 'admin',
  'status': 'active',
  'joined_at': '2026-09-01T00:00:00Z',
  'amount_scope': 'own',
  'contributions': [
    {'currency': 'EUR', 'amount_minor': 12345},
    {'currency': 'RWF', 'amount_minor': 3000},
  ],
};

class _ChangingRosterRepository extends CollectRepository {
  _ChangingRosterRepository() : super.fixture();
  int reads = 0;
  @override
  Future<List<CollectMember>> membersForCollection(String collectionId) async {
    reads++;
    return [
      CollectMember(
        publicId: state.currentProfile!.publicId,
        role: 'member',
        status: 'active',
        joinedAt: DateTime.utc(2026),
      ),
    ];
  }

  void changeAccount() {
    state = state.copyWith(
      currentProfile: const CollectProfile(
        id: 'next-user',
        publicId: '222222',
        whatsappPhone: '+250788222222',
        countryCode: 'RW',
        currencyCode: 'RWF',
      ),
    );
  }

  void refreshSnapshot() =>
      state = state.copyWith(lastSuccessfulSyncAt: DateTime.utc(2026, 9, 2));
}

Future<SupabaseClient> _client(Object? payload) async {
  final client = SupabaseClient(
    'http://127.0.0.1:1',
    'local-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/list_current_member_group_roster');
      expect(jsonDecode(request.body), {'p_collection_id': 'col-church'});
      return http.Response(
        jsonEncode(payload),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'local-test-access',
      'refresh_token': 'local-test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': '10000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-09-02T00:00:00Z',
      },
    }),
  );
  return client;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'roster amounts retain currency, precision, role and disclosure scope',
    () {
      final row = CollectMember.fromJson(_own);
      expect(row.publicId, '038491');
      expect(row.role, 'admin');
      expect(row.contributionTotals, {'EUR': 12345, 'RWF': 3000});
      expect(row.contributionCaption, 'Your contributions');
      expect(() => row.contributionTotals['EUR'] = 0, throwsUnsupportedError);
      final shared = CollectMember.fromJson(
        Map<String, dynamic>.of(_own)
          ..addAll(const {'public_id': '123456', 'amount_scope': 'shared'}),
      );
      expect(shared.contributionCaption, 'Shared contributions');
      final hidden = CollectMember.fromJson(
        Map<String, dynamic>.of(_own)
          ..addAll(const {'amount_scope': 'hidden', 'contributions': []}),
      );
      expect(hidden.contributionTotals, isEmpty);
      expect(hidden.contributionCaption, isNull);
    },
  );
  final invalidFields = <Map<String, Object?>>[
    {'public_id': 'name'},
    {'role': 'platform_owner'},
    {'status': 'unknown'},
    {'joined_at': 'yesterday'},
    {'amount_scope': 'all'},
    {'contributions': null},
    {
      'contributions': [
        {'currency': 'GBP', 'amount_minor': 100},
      ],
    },
    {
      'contributions': [
        {'currency': 'RWF', 'amount_minor': 0},
      ],
    },
    {
      'contributions': [
        {'currency': 'RWF', 'amount_minor': 1.5},
      ],
    },
    {
      'contributions': [
        {'currency': 'RWF', 'amount_minor': 100},
        {'currency': 'RWF', 'amount_minor': 200},
      ],
    },
    {'amount_scope': 'hidden'},
    {'amount_scope': 'shared', 'contributions': []},
  ];
  for (var i = 0; i < invalidFields.length; i++) {
    test('malformed roster row $i fails closed', () {
      expect(
        () => CollectMember.fromJson({..._own, ...invalidFields[i]}),
        throwsFormatException,
      );
    });
  }
  final invalidResponses = <Object?>[
    null,
    {},
    [null],
    [_own, _own],
    [
      {..._own, 'public_id': '123456'},
    ],
  ];
  for (var i = 0; i < invalidResponses.length; i++) {
    test(
      'roster RPC rejects malformed, duplicate or misattributed response $i',
      () async {
        final client = await _client(invalidResponses[i]);
        final repo = CollectRepository.fixture(supabase: client);
        addTearDown(client.dispose);
        addTearDown(repo.dispose);
        await expectLater(
          repo.membersForCollection('col-church'),
          throwsFormatException,
        );
      },
    );
  }
  test('member repository uses the authorized roster contract', () async {
    final client = await _client([_own]);
    final repo = CollectRepository.fixture(supabase: client);
    addTearDown(client.dispose);
    addTearDown(repo.dispose);
    final members = await repo.membersForCollection('col-church');
    expect(members.single.role, 'admin');
    expect(members.single.contributionTotals['EUR'], 12345);
  });
  test(
    'missing authentication never falls back to a synthetic live roster',
    () async {
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'local-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = CollectRepository.fixture(supabase: client);
      addTearDown(client.dispose);
      addTearDown(repo.dispose);
      await expectLater(
        repo.membersForCollection('col-church'),
        throwsStateError,
      );
    },
  );
  test(
    'synthetic transfer mirrors owner and former-owner roster roles',
    () async {
      final repo = CollectRepository.fixture();
      addTearDown(repo.dispose);
      await repo.transferCollectionOwnership(
        collectionId: 'col-church',
        publicId: '123456',
      );
      final members = await repo.membersForCollection('col-church');
      expect(members.map((member) => member.publicId).toSet().length, 2);
      expect(
        members.singleWhere((member) => member.publicId == '038491').role,
        'admin',
      );
      expect(
        members.singleWhere((member) => member.publicId == '123456').role,
        'owner',
      );
      expect(
        members
            .singleWhere((member) => member.publicId == '123456')
            .amountScope,
        'hidden',
      );
    },
  );
  test(
    'account and successful snapshot changes invalidate the roster',
    () async {
      final repo = _ChangingRosterRepository();
      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
      );
      addTearDown(container.dispose);
      final provider = groupMembersProvider('col-church');
      expect((await container.read(provider.future)).single.publicId, '038491');
      repo.changeAccount();
      expect((await container.read(provider.future)).single.publicId, '222222');
      repo.refreshSnapshot();
      await container.read(provider.future);
      expect(repo.reads, 3);
    },
  );
  test(
    'fixture never invents membership for an unjoined public group',
    () async {
      final repo = CollectRepository.fixture();
      addTearDown(repo.dispose);
      expect(
        await repo.membersForCollection('col-public-sport-fixture'),
        isEmpty,
      );
    },
  );
}
