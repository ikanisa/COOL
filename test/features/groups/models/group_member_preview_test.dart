import 'package:cool_app/features/groups/models/group_member_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupMemberPreview.fromJson', () {
    test('parses standard member', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': 'Jean',
        'is_admin': false,
        'is_anonymous': false,
        'joined_at': '2026-03-15T10:30:00.000Z',
      });

      expect(member.displayName, 'Jean');
      expect(member.isAdmin, isFalse);
      expect(member.isAnonymous, isFalse);
      expect(member.joinedAt, isNotNull);
      expect(member.joinedAt!.year, 2026);
    });

    test('parses admin member', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': 'Admin',
        'is_admin': true,
        'is_anonymous': false,
      });

      expect(member.isAdmin, isTrue);
      expect(member.joinedAt, isNull);
    });

    test('handles polymorphic boolean values (int, string)', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': 'Test',
        'is_admin': 1,
        'is_anonymous': 'true',
      });

      expect(member.isAdmin, isTrue);
      expect(member.isAnonymous, isTrue);
    });

    test('handles polymorphic boolean false variants', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': 'Test',
        'is_admin': 0,
        'is_anonymous': 'false',
      });

      expect(member.isAdmin, isFalse);
      expect(member.isAnonymous, isFalse);
    });

    test('defaults display_name to Member when missing', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'is_admin': false,
        'is_anonymous': false,
      });

      expect(member.displayName, 'Member');
    });

    test('handles null values gracefully', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': null,
        'is_admin': null,
        'is_anonymous': null,
        'joined_at': null,
      });

      expect(member.displayName, 'Member');
      expect(member.isAdmin, isFalse);
      expect(member.isAnonymous, isFalse);
      expect(member.joinedAt, isNull);
    });

    test('handles invalid date gracefully', () {
      final member = GroupMemberPreview.fromJson(<String, dynamic>{
        'display_name': 'Test',
        'is_admin': false,
        'is_anonymous': false,
        'joined_at': 'not-a-date',
      });

      expect(member.joinedAt, isNull);
    });
  });
}
