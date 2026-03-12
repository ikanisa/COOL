import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_contribution.dart';
import 'package:cool_app/features/groups/models/group_detail.dart';
import 'package:cool_app/features/groups/models/group_join_result.dart';
import 'package:cool_app/features/groups/models/group_member.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';

void main() {
  group('GroupsNotifier', () {
    late FakeGroupRepository repository;
    late GroupsNotifier notifier;

    setUp(() {
      repository = FakeGroupRepository();
      notifier = GroupsNotifier(
        repository: repository,
        authState: AuthState(user: _signedInUser),
      );
    });

    test('loads public groups from repository', () async {
      repository.publicGroups = <Group>[_publicGroup];

      await notifier.loadPublicGroups();

      expect(repository.lastPublicCountry, 'RW');
      expect(notifier.state.groups, hasLength(1));
      expect(notifier.state.groups.first.id, _publicGroup.id);
      expect(notifier.state.error, isNull);
    });

    test('loads invite preview into state', () async {
      repository.invitePreview = _inviteDetail.copyWith(isMember: false);

      await notifier.loadInvitePreview('abc12345');

      expect(repository.lastInvitePreviewCode, 'abc12345');
      expect(notifier.state.invitePreview?.group.id, _inviteDetail.group.id);
      expect(notifier.state.invitePreview?.isMember, isFalse);
      expect(notifier.state.error, isNull);
    });

    test('joins group via invite and upserts it into lists', () async {
      repository.joinResult = GroupJoinResult(
        detail: _inviteDetail.copyWith(isMember: true),
        status: 'joined',
      );

      final result = await notifier.joinGroupByInviteCode('ABCD1234');

      expect(result, isNotNull);
      expect(result!.didJoin, isTrue);
      expect(repository.lastJoinCode, 'ABCD1234');
      expect(notifier.state.invitePreview?.isMember, isTrue);
      expect(notifier.state.isJoiningGroup, isFalse);
      expect(notifier.state.joinGroupError, isNull);
      expect(
        notifier.state.groups.any(
          (group) => group.id == _inviteDetail.group.id,
        ),
        isTrue,
      );
    });
  });
}

class FakeGroupRepository implements GroupRepository {
  List<Group> myGroups = const <Group>[];
  List<Group> publicGroups = const <Group>[];
  GroupDetail? groupDetail;
  GroupDetail? invitePreview;
  GroupJoinResult? joinResult;
  String? lastPublicCountry;
  String? lastJoinCode;
  String? lastInvitePreviewCode;

  @override
  Future<Group> createGroup(Group group) async => group;

  @override
  Future<void> contribute(String groupId, int amount) async {}

  @override
  Future<GroupDetail?> getGroupById(String id, {String? country}) async =>
      groupDetail;

  @override
  Future<GroupDetail?> getGroupByInviteCode(
    String inviteCode, {
    String? country,
  }) async {
    lastInvitePreviewCode = inviteCode;
    return invitePreview;
  }

  @override
  Future<List<Group>> getMyGroups(String userId, {String? country}) async =>
      myGroups;

  @override
  Future<List<Group>> getPublicGroups(String country) async {
    lastPublicCountry = country;
    return publicGroups;
  }

  @override
  Future<GroupJoinResult> joinGroupByInviteCode(
    String inviteCode, {
    String? country,
  }) async {
    lastJoinCode = inviteCode;
    if (joinResult == null) {
      throw StateError('joinResult was not configured for this test.');
    }
    return joinResult!;
  }
}

const _signedInUser = UserProfile(
  id: 'user-1',
  phone: '+250788123456',
  fullName: 'Test User',
  momoNumber: '+250788123456',
  momoProvider: 'mtn_rwanda',
  country: 'RW',
  languageCode: 'en',
  isDriver: false,
);

const _publicGroup = Group(
  id: 'group-public',
  creatorId: 'owner-1',
  name: 'Public Savings Circle',
  type: 'saving',
  visibility: 'public',
  amount: 120000,
  targetAmount: 300000,
  country: 'RW',
  memberCount: 4,
  monthlyContribution: 10000,
  description: 'Public invite group',
  inviteCode: 'ABCD1234',
  frequency: 'Monthly',
);

const _inviteDetail = GroupDetail(
  group: Group(
    id: 'group-invite',
    creatorId: 'owner-2',
    name: 'Invite Circle',
    type: 'community',
    visibility: 'private',
    amount: 65000,
    targetAmount: 100000,
    country: 'RW',
    memberCount: 3,
    monthlyContribution: 5000,
    description: 'Emergency fund',
    inviteCode: 'ABCD1234',
    frequency: 'Weekly',
  ),
  members: <GroupMember>[],
  recentContributions: <GroupContribution>[],
);
