class GroupContribution {
  const GroupContribution({
    this.id,
    required this.groupId,
    required this.userId,
    required this.amount,
    required this.status,
    this.contributorName,
    this.createdAt,
  });

  final String? id;
  final String groupId;
  final String userId;
  final int amount;
  final String status;
  final String? contributorName;
  final DateTime? createdAt;

  factory GroupContribution.fromJson(Map<String, dynamic> json) {
    return GroupContribution(
      id: json['id']?.toString(),
      groupId: json['group_id']?.toString() ?? '',
      userId:
          json['user_id']?.toString() ?? json['member_id']?.toString() ?? '',
      amount: _asInt(json['amount']),
      status: json['status']?.toString() ?? 'pending',
      contributorName:
          json['contributor_name']?.toString() ??
          json['display_name']?.toString(),
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'id': id,
      'group_id': groupId,
      'user_id': userId,
      'amount': amount,
      'status': status,
      'contributor_name': contributorName,
      'created_at': createdAt?.toIso8601String(),
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

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
