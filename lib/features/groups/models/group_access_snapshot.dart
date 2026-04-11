class GroupAccessSnapshot {
  const GroupAccessSnapshot({
    required this.groupId,
    required this.isMember,
    required this.isCreator,
    required this.isGroupAdmin,
    required this.isBankCustodyAdmin,
    required this.canViewTransactions,
    required this.canManageSettings,
    required this.canExportLedger,
  });

  final String groupId;
  final bool isMember;
  final bool isCreator;
  final bool isGroupAdmin;
  final bool isBankCustodyAdmin;
  final bool canViewTransactions;
  final bool canManageSettings;
  final bool canExportLedger;

  bool get isPrivilegedAdmin => isCreator || isGroupAdmin || isBankCustodyAdmin;

  factory GroupAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return GroupAccessSnapshot(
      groupId: json['group_id']?.toString() ?? '',
      isMember: _asBool(json['is_member']),
      isCreator: _asBool(json['is_creator']),
      isGroupAdmin: _asBool(json['is_group_admin']),
      isBankCustodyAdmin: _asBool(json['is_bank_custody_admin']),
      canViewTransactions: _asBool(json['can_view_transactions']),
      canManageSettings: _asBool(json['can_manage_settings']),
      canExportLedger: _asBool(json['can_export_ledger']),
    );
  }
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return normalized == 'true' || normalized == '1';
}
