class GroupMemberPreview {
  const GroupMemberPreview({
    required this.displayName,
    required this.isAdmin,
    required this.isAnonymous,
    this.joinedAt,
  });

  final String displayName;
  final bool isAdmin;
  final bool isAnonymous;
  final DateTime? joinedAt;

  factory GroupMemberPreview.fromJson(Map<String, dynamic> json) {
    return GroupMemberPreview(
      displayName: json['display_name']?.toString() ?? 'Member',
      isAdmin: _asBool(json['is_admin']),
      isAnonymous: _asBool(json['is_anonymous']),
      joinedAt: _parseDateTime(json['joined_at']),
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

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
