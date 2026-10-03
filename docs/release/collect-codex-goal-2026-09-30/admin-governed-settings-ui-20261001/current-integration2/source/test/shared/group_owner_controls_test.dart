import '../fixtures/collect_repository_fixture.dart';

import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _GroupControlRepository extends FixtureCollectRepository {
  _GroupControlRepository({bool publicGroup = false, bool platform = false})
    : super() {
    state = state.copyWith(
      collections: [
        for (final group in state.collections)
          if (group.id == 'qa-private-group')
            group.copyWith(isPublic: publicGroup, isPlatformSponsored: platform)
          else
            group,
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in ['platform', 'public']) {
    test('$mode group owner controls stay in central Admin', () async {
      final repo = _GroupControlRepository(
        publicGroup: mode == 'public',
        platform: mode == 'platform',
      );
      addTearDown(repo.dispose);
      final before = repo.state;
      await expectLater(
        repo.archiveCollection('qa-private-group'),
        throwsStateError,
      );
      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.transferCollectionOwnership(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        throwsStateError,
      );
      expect(identical(repo.state, before), isTrue);
    });
  }

  for (final id in ['abc123456', '123-456', '1234567', '12345']) {
    test('ownership transfer rejects malformed ID $id', () async {
      final repo = FixtureCollectRepository();
      addTearDown(repo.dispose);
      final before = repo.state;
      await expectLater(
        repo.transferCollectionOwnership(
          collectionId: 'qa-private-group',
          publicId: id,
        ),
        throwsFormatException,
      );
      expect(identical(repo.state, before), isTrue);
    });
  }

  test('former owner immediately loses owner controls in local flow', () async {
    final repo = FixtureCollectRepository();
    addTearDown(repo.dispose);
    final receiver = repo.collectionById('qa-private-group').receiverMomoNumber;
    final originalProfile = repo.state.currentProfile;
    await repo.transferCollectionOwnership(
      collectionId: 'qa-private-group',
      publicId: '123456',
    );
    expect(repo.state.currentProfile, originalProfile);
    expect(
      repo.collectionById('qa-private-group').receiverMomoNumber,
      receiver,
    );
    await expectLater(
      repo.archiveCollection('qa-private-group'),
      throwsStateError,
    );
    await expectLater(
      repo.transferCollectionOwnership(
        collectionId: 'qa-private-group',
        publicId: '234567',
      ),
      throwsStateError,
    );
    await expectLater(
      repo.inviteCollectionAdmin(
        collectionId: 'qa-private-group',
        publicId: '345678',
      ),
      throwsStateError,
    );
  });

  test(
    'archive preserves contributions and prevents ownership transfer',
    () async {
      final repo = FixtureCollectRepository();
      addTearDown(repo.dispose);
      final contributions = repo.state.contributions;
      final receiver = repo
          .collectionById('qa-private-group')
          .receiverMomoNumber;
      await repo.archiveCollection('qa-private-group');
      expect(repo.collectionById('qa-private-group').isArchived, isTrue);
      expect(
        repo.collectionById('qa-private-group').receiverMomoNumber,
        receiver,
      );
      expect(repo.state.contributions, contributions);
      await expectLater(
        repo.transferCollectionOwnership(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'group admin request rejects non-members without platform pre-approval',
    () async {
      final repo = FixtureCollectRepository();
      addTearDown(repo.dispose);
      final before = repo.state;
      final membersBefore = await repo.membersForCollection('qa-private-group');
      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Choose another active group member.',
          ),
        ),
      );
      expect(identical(repo.state, before), isTrue);
      expect(
        (await repo.membersForCollection('qa-private-group')).length,
        membersBefore.length,
      );
    },
  );

  for (final target in ['123456', '038491', '+250788123456', '']) {
    test(
      'group admin request validates $target without platform approval or retired RPC',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'http://127.0.0.1:1',
          'local-test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response('{}', 200, request: request);
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
        final repo = FixtureCollectRepository(supabase: client);
        addTearDown(repo.dispose);
        expect(repo.isLive, isTrue);
        final before = repo.state;
        await expectLater(
          repo.inviteCollectionAdmin(
            collectionId: 'qa-private-group',
            publicId: target,
          ),
          throwsFormatException,
        );
        if (target == '123456') {
          expect(requests.single.url.path, '/rest/v1/rpc/add_group_admin');
          expect(jsonDecode(requests.single.body), {
            'collection': 'qa-private-group',
            'member_public_id': '123456',
          });
        } else {
          expect(requests, isEmpty);
        }
        expect(identical(repo.state, before), isTrue);
      },
    );
  }

  test(
    'owner promotes active member idempotently without changing payments',
    () async {
      final joined = DateTime.utc(2026, 8, 1);
      final repo = FixtureCollectRepository(
        fixtureAdditionalMembers: {
          'qa-private-group': [
            CollectMember(
              publicId: '123456',
              role: 'member',
              status: 'active',
              joinedAt: joined,
            ),
          ],
        },
      );
      addTearDown(repo.dispose);
      final before = repo.state;
      for (var retry = 0; retry < 2; retry++) {
        await repo.inviteCollectionAdmin(
          collectionId: 'qa-private-group',
          publicId: ' 123456 ',
        );
        final roster = await repo.membersForCollection('qa-private-group');
        expect(roster.length, 2);
        final member = roster.singleWhere(
          (member) => member.publicId == '123456',
        );
        expect(member.role, 'admin');
        expect(member.status, 'active');
        expect(member.joinedAt, joined);
        expect(member.contributionTotals, isEmpty);
      }
      expect(repo.state.currentProfile, same(before.currentProfile));
      expect(repo.state.collections, before.collections);
      expect(repo.state.contributions, before.contributions);
      expect(repo.state.paymentIntents, before.paymentIntents);
    },
  );

  for (final status in ['invited', 'left', 'removed']) {
    test('owner cannot promote $status member', () async {
      final repo = FixtureCollectRepository(
        fixtureAdditionalMembers: {
          'qa-private-group': [
            CollectMember(
              publicId: '123456',
              role: 'member',
              status: status,
              joinedAt: DateTime.utc(2026, 8, 1),
            ),
          ],
        },
      );
      addTearDown(repo.dispose);
      await expectLater(
        repo.inviteCollectionAdmin(
          collectionId: 'qa-private-group',
          publicId: '123456',
        ),
        throwsFormatException,
      );
      expect(
        (await repo.membersForCollection('qa-private-group')).last.status,
        status,
      );
    });
  }

  test(
    'ordinary member creates and owns a group without platform approval',
    () async {
      final repo = FixtureCollectRepository(
        profileOverride: const CollectProfile(
          id: 'ordinary-member',
          publicId: '654321',
          whatsappPhone: '+250788654321',
          countryCode: 'RW',
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788654321',
        ),
      );
      addTearDown(repo.dispose);
      final profileBefore = repo.state.currentProfile;
      final group = await repo.createCollection(
        title: 'Member-created group',
        description: 'No platform Admin approval',
        receiverMomoNumber: '0788654321',
      );
      expect(group.creatorUserId, 'ordinary-member');
      expect(group.isPlatformSponsored, isFalse);
      expect(repo.state.currentProfile, profileBefore);
      expect((await repo.membersForCollection(group.id)).single.role, 'owner');
    },
  );
}
