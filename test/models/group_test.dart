import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/features/groups/models/group.dart';

void main() {
  group('Group.fromJson', () {
    test('parses standard group JSON', () {
      final json = {
        'id': 'grp-1',
        'creator_id': 'user-1',
        'name': 'Savings Club',
        'type': 'saving',
        'visibility': 'private',
        'amount': 50000,
        'target_amount': 200000,
        'country': 'RW',
        'member_count': 5,
      };

      final group = Group.fromJson(json);

      expect(group.id, 'grp-1');
      expect(group.creatorId, 'user-1');
      expect(group.name, 'Savings Club');
      expect(group.type, 'saving');
      expect(group.visibility, 'private');
      expect(group.amount, 50000);
      expect(group.targetAmount, 200000);
      expect(group.country, 'RW');
      expect(group.memberCount, 5);
    });

    test('normalizes visibility from various formats', () {
      expect(
        Group.fromJson({
          'creator_id': 'u',
          'name': 'Test',
          'type': 'saving',
          'visibility': 'Public Group',
          'amount': 0,
          'target_amount': 0,
          'country': '',
        }).visibility,
        'public',
      );

      expect(
        Group.fromJson({
          'creator_id': 'u',
          'name': 'Test',
          'type': 'saving',
          'visibility': 'PRIVATE',
          'amount': 0,
          'target_amount': 0,
          'country': '',
        }).visibility,
        'private',
      );
    });

    test('normalizes type from fund_purpose enum', () {
      expect(
        Group.fromJson({
          'creator_id': 'u',
          'name': 'Test',
          'fund_purpose': 'COMMUNITY_COLLECTION',
          'visibility': 'public',
          'amount': 0,
          'target_amount': 0,
          'country': '',
        }).type,
        'community',
      );

      expect(
        Group.fromJson({
          'creator_id': 'u',
          'name': 'Test',
          'fund_purpose': 'GROUP_SAVINGS',
          'visibility': 'private',
          'amount': 0,
          'target_amount': 0,
          'country': '',
        }).type,
        'saving',
      );
    });

    test('falls back group_name to name', () {
      final json = {
        'creator_id': 'u',
        'group_name': 'Legacy Name',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      };

      expect(Group.fromJson(json).name, 'Legacy Name');
    });

    test('extracts member_count from nested member_counts array', () {
      final json = {
        'creator_id': 'u',
        'name': 'Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'member_counts': [
          {'count': 12},
        ],
      };

      expect(Group.fromJson(json).memberCount, 12);
    });

    test('extracts member_count from members list length', () {
      final json = {
        'creator_id': 'u',
        'name': 'Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
        'members': ['a', 'b', 'c'],
      };

      expect(Group.fromJson(json).memberCount, 3);
    });

    test('reads amount from alternative keys', () {
      final json = {
        'creator_id': 'u',
        'name': 'Test',
        'type': 'saving',
        'visibility': 'private',
        'balance': 75000,
        'expected_amount': 150000,
        'country': '',
      };

      final group = Group.fromJson(json);
      expect(group.amount, 75000);
      expect(group.targetAmount, 150000);
    });

    test('handles string number values', () {
      final json = {
        'creator_id': 'u',
        'name': 'Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': '10000',
        'target_amount': '50000',
        'country': '',
      };

      final group = Group.fromJson(json);
      expect(group.amount, 10000);
      expect(group.targetAmount, 50000);
    });

    test('defaults to 0 for missing numeric values', () {
      final json = {
        'creator_id': 'u',
        'name': 'Test',
        'type': 'saving',
        'visibility': 'private',
        'country': '',
      };

      final group = Group.fromJson(json);
      expect(group.amount, 0);
      expect(group.targetAmount, 0);
      expect(group.memberCount, 0);
    });
  });

  group('Group.toJson', () {
    test('roundtrips through fromJson → toJson', () {
      final original = {
        'id': 'grp-rt',
        'creator_id': 'user-rt',
        'name': 'Roundtrip Group',
        'type': 'community',
        'visibility': 'public',
        'amount': 100000,
        'target_amount': 500000,
        'country': 'RW',
        'member_count': 10,
      };

      final group = Group.fromJson(original);
      final json = group.toJson();

      expect(json['id'], 'grp-rt');
      expect(json['creator_id'], 'user-rt');
      expect(json['name'], 'Roundtrip Group');
      expect(json['type'], 'community');
      expect(json['visibility'], 'public');
      expect(json['amount'], 100000);
    });

    test('removes null optional fields', () {
      final json = {
        'id': 'grp-null',
        'creator_id': 'u',
        'name': 'Null Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': 0,
        'target_amount': 0,
        'country': '',
      };

      final output = Group.fromJson(json).toJson();

      expect(output.containsKey('description'), isFalse);
      expect(output.containsKey('bank_partner'), isFalse);
      expect(output.containsKey('invite_code'), isFalse);
    });
  });

  group('Group.toInsertJson', () {
    test('excludes id and timestamps', () {
      final group = Group.fromJson({
        'id': 'should-be-excluded',
        'creator_id': 'user-insert',
        'name': 'Insert Test',
        'type': 'saving',
        'visibility': 'private',
        'amount': 1000,
        'target_amount': 5000,
        'country': 'RW',
        'created_at': '2025-01-01T00:00:00.000Z',
      });

      final insertJson = group.toInsertJson();

      expect(insertJson.containsKey('id'), isFalse);
      expect(insertJson.containsKey('created_at'), isFalse);
      expect(insertJson['creator_id'], 'user-insert');
      expect(insertJson['name'], 'Insert Test');
    });
  });

  group('Group.copyWith', () {
    test('updates specified fields only', () {
      final group = Group.fromJson({
        'id': 'copy-grp',
        'creator_id': 'u',
        'name': 'Original',
        'type': 'saving',
        'visibility': 'private',
        'amount': 1000,
        'target_amount': 5000,
        'country': 'RW',
      });

      final updated = group.copyWith(name: 'Updated', amount: 9999);

      expect(updated.name, 'Updated');
      expect(updated.amount, 9999);
      expect(updated.id, 'copy-grp');
      expect(updated.country, 'RW');
      expect(updated.type, 'saving');
    });
  });
}
