import 'package:cool_app/features/groups/models/group_access_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses mixed boolean values from json', () {
    final snapshot = GroupAccessSnapshot.fromJson(<String, dynamic>{
      'group_id': 'group-1',
      'is_member': 1,
      'is_creator': 'true',
      'is_group_admin': false,
      'is_bank_custody_admin': '0',
      'can_view_transactions': '1',
      'can_manage_settings': true,
      'can_export_ledger': 0,
    });

    expect(snapshot.groupId, 'group-1');
    expect(snapshot.isMember, isTrue);
    expect(snapshot.isCreator, isTrue);
    expect(snapshot.isGroupAdmin, isFalse);
    expect(snapshot.isBankCustodyAdmin, isFalse);
    expect(snapshot.canViewTransactions, isTrue);
    expect(snapshot.canManageSettings, isTrue);
    expect(snapshot.canExportLedger, isFalse);
    expect(snapshot.isPrivilegedAdmin, isTrue);
  });
}
