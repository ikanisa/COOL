import 'package:cool_app/features/groups/models/group_join_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupJoinResult.fromJson', () {
    test('parses joined status', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{
        'status': 'joined',
        'group_id': 'g-123',
      });

      expect(result.status, 'joined');
      expect(result.groupId, 'g-123');
      expect(result.isJoined, isTrue);
      expect(result.isAlreadyMember, isFalse);
    });

    test('parses already_member status', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{
        'status': 'already_member',
        'group_id': 'g-456',
      });

      expect(result.isJoined, isTrue);
      expect(result.isAlreadyMember, isTrue);
    });

    test('parses success status', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{
        'status': 'success',
        'group_id': 'g-789',
      });

      expect(result.isJoined, isTrue);
    });

    test('parses error status', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{
        'status': 'error',
        'message': 'Group not found.',
      });

      expect(result.isJoined, isFalse);
      expect(result.isAlreadyMember, isFalse);
      expect(result.message, 'Group not found.');
    });

    test('handles missing status gracefully', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{});

      expect(result.status, 'error');
      expect(result.isJoined, isFalse);
      expect(result.groupId, isNull);
    });

    test('handles null values', () {
      final result = GroupJoinResult.fromJson(<String, dynamic>{
        'status': null,
        'group_id': null,
        'message': null,
      });

      expect(result.status, 'error');
      expect(result.groupId, isNull);
      expect(result.message, isNull);
    });
  });
}
