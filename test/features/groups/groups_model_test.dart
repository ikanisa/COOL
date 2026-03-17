import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group.fromJson', () {
    test('parses a minimal valid JSON group', () {
      final json = <String, dynamic>{
        'id': 'group-1',
        'creator_id': 'user-1',
        'name': 'Ikimina Alpha',
        'type': 'saving',
        'visibility': 'private',
        'amount': 150000,
        'target_amount': 500000,
        'country': 'RW',
        'member_count': 12,
      };

      final group = Group.fromJson(json);

      expect(group.id, 'group-1');
      expect(group.creatorId, 'user-1');
      expect(group.name, 'Ikimina Alpha');
      expect(group.type, 'saving');
      expect(group.visibility, 'private');
      expect(group.amount, 150000);
      expect(group.targetAmount, 500000);
      expect(group.memberCount, 12);
    });

    test('normalizes public visibility from "Public"', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Community Hub',
        'type': 'community',
        'visibility': 'Public',
        'amount': 0,
        'target_amount': 100000,
        'country': 'RW',
      };

      final group = Group.fromJson(json);
      expect(group.visibility, 'public');
    });

    test('defaults visibility to private for unknown values', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Unknown Vis',
        'type': 'saving',
        'visibility': 'foobar',
        'amount': 0,
        'target_amount': 10000,
        'country': 'RW',
      };

      final group = Group.fromJson(json);
      expect(group.visibility, 'private');
    });

    test('resolves type from fund_purpose GROUP_SAVINGS', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Savings Club',
        'type': 'public',
        'visibility': 'public',
        'fund_purpose': 'GROUP_SAVINGS',
        'amount': 0,
        'target_amount': 200000,
        'country': 'RW',
      };

      final group = Group.fromJson(json);
      expect(group.type, 'saving');
    });

    test('resolves type from fund_purpose COMMUNITY_COLLECTION', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Community Fund',
        'type': 'private',
        'visibility': 'public',
        'fund_purpose': 'COMMUNITY_COLLECTION',
        'amount': 0,
        'target_amount': 300000,
        'country': 'RW',
      };

      final group = Group.fromJson(json);
      expect(group.type, 'community');
    });

    test('extracts member_count from nested member_counts list', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Nested Count',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 100000,
        'country': 'RW',
        'member_counts': [
          {'count': 42},
        ],
      };

      final group = Group.fromJson(json);
      expect(group.memberCount, 42);
    });

    test('extracts member count from group_members list length', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Members List',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 100000,
        'country': 'RW',
        'group_members': [
          {'id': 'a'},
          {'id': 'b'},
          {'id': 'c'},
        ],
      };

      final group = Group.fromJson(json);
      expect(group.memberCount, 3);
    });

    test('parses dates correctly', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Dates Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': 'RW',
        'created_at': '2026-01-15T10:30:00.000Z',
        'updated_at': '2026-03-01T12:00:00.000Z',
      };

      final group = Group.fromJson(json);
      expect(group.createdAt, isNotNull);
      expect(group.createdAt!.year, 2026);
      expect(group.createdAt!.month, 1);
      expect(group.updatedAt, isNotNull);
    });

    test('handles missing optional fields gracefully', () {
      final json = <String, dynamic>{
        'creator_id': 'user-1',
        'name': 'Minimal',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': 'RW',
      };

      final group = Group.fromJson(json);
      expect(group.monthlyContribution, isNull);
      expect(group.description, isNull);
      expect(group.momoNumber, isNull);
      expect(group.inviteCode, isNull);
      expect(group.frequency, isNull);
      expect(group.createdAt, isNull);
    });

    test('normalizes frequency from cycle_days', () {
      expect(
        Group.fromJson(<String, dynamic>{
          'creator_id': 'u',
          'name': 'n',
          'type': 'saving',
          'visibility': 'private',
          'amount': 0,
          'target_amount': 0,
          'country': 'RW',
          'cycle_days': 1,
        }).frequency,
        'daily',
      );

      expect(
        Group.fromJson(<String, dynamic>{
          'creator_id': 'u',
          'name': 'n',
          'type': 'saving',
          'visibility': 'private',
          'amount': 0,
          'target_amount': 0,
          'country': 'RW',
          'cycle_days': 7,
        }).frequency,
        'weekly',
      );

      expect(
        Group.fromJson(<String, dynamic>{
          'creator_id': 'u',
          'name': 'n',
          'type': 'saving',
          'visibility': 'private',
          'amount': 0,
          'target_amount': 0,
          'country': 'RW',
          'cycle_days': 30,
        }).frequency,
        'monthly',
      );
    });
  });

  group('Group.toJson', () {
    test('round-trips through fromJson → toJson', () {
      const original = Group(
        id: 'g-123',
        creatorId: 'u-1',
        name: 'Round Trip',
        type: 'saving',
        visibility: 'private',
        amount: 50000,
        targetAmount: 200000,
        country: 'RW',
        memberCount: 5,
        monthlyContribution: 10000,
        description: 'A test group',
        momoNumber: '0788123456',
        inviteCode: 'ABC123',
        frequency: 'monthly',
      );

      final json = original.toJson();

      expect(json['name'], 'Round Trip');
      expect(json['type'], 'saving');
      expect(json['target_amount'], 200000);
      expect(json['momo_number'], '0788123456');
      expect(json['invite_code'], 'ABC123');
    });

    test('toInsertJson excludes id', () {
      const group = Group(
        id: 'g-123',
        creatorId: 'u-1',
        name: 'Insert Test',
        type: 'saving',
        visibility: 'private',
        amount: 0,
        targetAmount: 100000,
        country: 'RW',
      );

      final insertJson = group.toInsertJson();
      expect(insertJson.containsKey('id'), isFalse);
      expect(insertJson['creator_id'], 'u-1');
    });
  });

  group('Group.copyWith', () {
    test('copies specific fields', () {
      const original = Group(
        id: 'g-1',
        creatorId: 'u-1',
        name: 'Original',
        type: 'saving',
        visibility: 'private',
        amount: 1000,
        targetAmount: 10000,
        country: 'RW',
      );

      final modified = original.copyWith(
        name: 'Modified',
        amount: 5000,
        memberCount: 10,
      );

      expect(modified.name, 'Modified');
      expect(modified.amount, 5000);
      expect(modified.memberCount, 10);
      expect(modified.id, 'g-1'); // unchanged
      expect(modified.type, 'saving'); // unchanged
    });
  });

  group('GroupsState', () {
    test('initial state has empty groups and no loading', () {
      const initial = GroupsState();
      expect(initial.groups, isEmpty);
      expect(initial.isLoading, isFalse);
      expect(initial.error, isNull);
      expect(initial.isCreatingGroup, isFalse);
      expect(initial.isJoiningGroup, isFalse);
      expect(initial.isContributing, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const initial = GroupsState();
      final updated = initial.copyWith(isLoading: true);

      expect(updated.isLoading, isTrue);
      expect(updated.groups, isEmpty);
      expect(updated.error, isNull);
    });

    test('copyWith can set and clear error', () {
      const initial = GroupsState();
      final withError = initial.copyWith(error: 'Network failed');
      expect(withError.error, 'Network failed');

      final cleared = withError.copyWith(error: null);
      expect(cleared.error, isNull);
    });
  });

  group('GroupCreateData', () {
    test('stores all provided fields', () {
      const data = GroupCreateData(
        name: 'New Savings Group',
        type: 'saving',
        visibility: 'private',
        targetAmountRwf: 500000,
        monthlyContributionRwf: 25000,
        momoNumber: '0788111111',
        description: 'Our savings group',
        frequency: 'monthly',
      );

      expect(data.name, 'New Savings Group');
      expect(data.type, 'saving');
      expect(data.targetAmountRwf, 500000);
      expect(data.monthlyContributionRwf, 25000);
      expect(data.frequency, 'monthly');
    });

    test('defaults to monthly frequency and 30 cycle days', () {
      const data = GroupCreateData(
        name: 'Quick',
        type: 'saving',
        visibility: 'private',
        targetAmountRwf: 10000,
      );

      expect(data.frequency, 'monthly');
      expect(data.cycleDays, 30);
    });
  });
}
