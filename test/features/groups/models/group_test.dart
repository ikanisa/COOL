import 'package:cool_app/features/groups/models/group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group.fromJson', () {
    test('parses a standard public group', () {
      final group = Group.fromJson(<String, dynamic>{
        'id': 'g-001',
        'creator_id': 'u-001',
        'name': 'Savings Circle',
        'type': 'saving',
        'visibility': 'public',
        'amount': 50000,
        'target_amount': 200000,
        'country': 'RW',
        'member_count': 12,
        'description': 'Monthly savings group',
        'invite_code': 'ABC123',
        'frequency': 'monthly',
        'created_at': '2026-03-01T10:00:00.000Z',
      });

      expect(group.id, 'g-001');
      expect(group.creatorId, 'u-001');
      expect(group.name, 'Savings Circle');
      expect(group.type, 'saving');
      expect(group.visibility, 'public');
      expect(group.amount, 50000);
      expect(group.targetAmount, 200000);
      expect(group.country, 'RW');
      expect(group.memberCount, 12);
      expect(group.inviteCode, 'ABC123');
      expect(group.frequency, 'monthly');
      expect(group.createdAt, isNotNull);
    });

    test('normalizes visibility from is_public boolean fallback', () {
      final publicGroup = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'is_public': true,
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });
      expect(publicGroup.visibility, 'public');

      final privateGroup = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'is_public': false,
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });
      expect(privateGroup.visibility, 'private');
    });

    test('normalizes type from fund_purpose COMMUNITY_COLLECTION', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Community Fund',
        'fund_purpose': 'community_collection',
        'visibility': 'public',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });

      expect(group.type, 'community');
    });

    test('normalizes type from fund_purpose GROUP_SAVINGS', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Saver Group',
        'fund_purpose': 'group_savings',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });

      expect(group.type, 'saving');
    });

    test('falls back public type to community when type is "public"', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'type': 'public',
        'visibility': 'public',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });

      expect(group.type, 'community');
    });

    test('extracts amount from multiple field aliases', () {
      final fromBalance = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'balance': 1500,
        'target_amount': 0,
        'country': '',
      });
      expect(fromBalance.amount, 1500);

      final fromRaised = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'raised_amount': 2500,
        'target_amount': 0,
        'country': '',
      });
      expect(fromRaised.amount, 2500);
    });

    test('extracts member count from member_counts array', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'member_counts': [
          {'count': 8},
        ],
      });

      expect(group.memberCount, 8);
    });

    test('extracts member count from group_members list length', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'group_members': [
          {'id': '1'},
          {'id': '2'},
          {'id': '3'},
        ],
      });

      expect(group.memberCount, 3);
    });

    test('normalizes frequency from cycle_days', () {
      final daily = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'cycle_days': 1,
      });
      expect(daily.frequency, 'daily');

      final weekly = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'cycle_days': 7,
      });
      expect(weekly.frequency, 'weekly');

      final monthly = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'cycle_days': 30,
      });
      expect(monthly.frequency, 'monthly');

      final oneOff = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'name': 'Test',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'cycle_days': 0,
      });
      expect(oneOff.frequency, 'one_off');
    });

    test('uses group_name as name fallback', () {
      final group = Group.fromJson(<String, dynamic>{
        'creator_id': 'u-001',
        'group_name': 'Fallback Name',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      });

      expect(group.name, 'Fallback Name');
    });

    test('handles fully empty json gracefully', () {
      final group = Group.fromJson(<String, dynamic>{});

      expect(group.id, isNull);
      expect(group.creatorId, '');
      expect(group.name, '');
      expect(group.visibility, 'private');
      expect(group.type, 'saving');
      expect(group.amount, 0);
      expect(group.targetAmount, 0);
      expect(group.memberCount, 0);
    });
  });

  group('Group.toJson', () {
    test('serializes and removes null fields', () {
      const group = Group(
        id: 'g-010',
        creatorId: 'u-010',
        name: 'Test Group',
        type: 'saving',
        visibility: 'private',
        amount: 10000,
        targetAmount: 50000,
        country: 'RW',
      );

      final json = group.toJson();
      expect(json['id'], 'g-010');
      expect(json['name'], 'Test Group');
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('invite_code'), isFalse);
    });
  });

  group('Group.toInsertJson', () {
    test('excludes id field', () {
      const group = Group(
        id: 'g-020',
        creatorId: 'u-020',
        name: 'Insert Test',
        type: 'community',
        visibility: 'public',
        amount: 0,
        targetAmount: 100000,
        country: 'RW',
      );

      final json = group.toInsertJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['creator_id'], 'u-020');
    });
  });

  group('Group.copyWith', () {
    test('creates modified copy preserving unchanged fields', () {
      const original = Group(
        id: 'g-100',
        creatorId: 'u-100',
        name: 'Original',
        type: 'saving',
        visibility: 'private',
        amount: 5000,
        targetAmount: 10000,
        country: 'RW',
        memberCount: 5,
      );

      final copy = original.copyWith(name: 'Updated', amount: 7500);

      expect(copy.name, 'Updated');
      expect(copy.amount, 7500);
      expect(copy.id, 'g-100');
      expect(copy.creatorId, 'u-100');
      expect(copy.memberCount, 5);
    });
  });
}
