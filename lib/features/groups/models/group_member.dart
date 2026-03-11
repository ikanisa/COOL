class GroupMember {
  const GroupMember({
    required this.userId,
    required this.contributionAmount,
    this.displayName,
    this.isAdmin = false,
    this.isAnonymous = false,
    this.joinedAt,
  });

  final String userId;
  final int contributionAmount;
  final String? displayName;
  final bool isAdmin;
  final bool isAnonymous;
  final DateTime? joinedAt;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final nestedUser = json['users'];
    return GroupMember(
      userId: json['user_id']?.toString() ?? '',
      contributionAmount: _asInt(
        json['contribution_amount'] ?? json['total_contribution'],
      ),
      displayName:
          json['display_name']?.toString() ??
          (json['member'] is Map
              ? (json['member'] as Map)['full_name']?.toString()
              : null) ??
          (nestedUser is Map
              ? nestedUser['full_name']?.toString() ??
                    nestedUser['name']?.toString()
              : null),
      isAdmin:
          _asBool(json['is_admin']) ||
          const {
            'admin',
            'owner',
            'chairperson',
          }.contains(json['role']?.toString().toLowerCase()),
      isAnonymous: _asBool(json['is_anonymous']),
      joinedAt: _parseDateTime(json['joined_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'user_id': userId,
      'display_name': displayName,
      'is_admin': isAdmin,
      'is_anonymous': isAnonymous,
      'contribution_amount': contributionAmount,
      'joined_at': joinedAt?.toIso8601String(),
    };

    data.removeWhere((_, value) => value == null);
    return data;
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
