import '../../groups/models/group.dart';

class BankAdminPage<T> {
  const BankAdminPage({this.entries = const [], this.totalCount = 0});

  final List<T> entries;
  final int totalCount;
}

class BankAdminGroupSummary {
  const BankAdminGroupSummary({
    required this.group,
    this.adminCount = 0,
    this.contributionCount = 0,
    this.contributionTotal = 0,
    this.lastContributionAt,
  });

  final Group group;
  final int adminCount;
  final int contributionCount;
  final int contributionTotal;
  final DateTime? lastContributionAt;

  String get id => group.id ?? '';

  factory BankAdminGroupSummary.fromJson(Map<String, dynamic> json) {
    return BankAdminGroupSummary(
      group: Group.fromJson(json),
      adminCount: _asInt(json['admin_count']),
      contributionCount: _asInt(json['contribution_count']),
      contributionTotal: _asInt(json['contribution_total']),
      lastContributionAt: _parseDateTime(json['last_contribution_at']),
    );
  }
}

class BankAdminMemberRecord {
  const BankAdminMemberRecord({
    required this.groupId,
    required this.groupName,
    required this.userId,
    required this.displayName,
    required this.contributionAmount,
    this.isAdmin = false,
    this.isAnonymous = false,
    this.joinedAt,
  });

  final String groupId;
  final String groupName;
  final String userId;
  final String displayName;
  final int contributionAmount;
  final bool isAdmin;
  final bool isAnonymous;
  final DateTime? joinedAt;

  factory BankAdminMemberRecord.fromJson(Map<String, dynamic> json) {
    return BankAdminMemberRecord(
      groupId: json['group_id']?.toString() ?? '',
      groupName: json['group_name']?.toString() ?? 'Savings group',
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Member',
      contributionAmount: _asInt(json['contribution_amount']),
      isAdmin: _asBool(json['is_admin']),
      isAnonymous: _asBool(json['is_anonymous']),
      joinedAt: _parseDateTime(json['joined_at']),
    );
  }
}

class BankAdminContributionRecord {
  const BankAdminContributionRecord({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.userId,
    required this.contributorName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.reference,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String userId;
  final String contributorName;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String? reference;

  factory BankAdminContributionRecord.fromJson(Map<String, dynamic> json) {
    return BankAdminContributionRecord(
      id: json['contribution_id']?.toString() ?? '',
      groupId: json['group_id']?.toString() ?? '',
      groupName: json['group_name']?.toString() ?? 'Savings group',
      userId: json['user_id']?.toString() ?? '',
      contributorName: json['contributor_name']?.toString() ?? 'Member',
      amount: _asInt(json['amount']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _parseDateTime(json['created_at']) ?? DateTime.now(),
      reference: _nonEmpty(json['momo_reference']),
    );
  }
}

class BankAdminAllocationReviewItem {
  const BankAdminAllocationReviewItem({
    required this.reviewId,
    required this.groupId,
    required this.groupName,
    required this.payerName,
    required this.matchStatus,
    required this.reason,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.payerUserId,
    this.reference,
    this.provider,
    this.payeeDigits,
  });

  final String reviewId;
  final String groupId;
  final String groupName;
  final String? payerUserId;
  final String payerName;
  final String matchStatus;
  final String reason;
  final int amount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reference;
  final String? provider;
  final String? payeeDigits;

  factory BankAdminAllocationReviewItem.fromJson(Map<String, dynamic> json) {
    return BankAdminAllocationReviewItem(
      reviewId: json['review_id']?.toString() ?? '',
      groupId: json['group_id']?.toString() ?? '',
      groupName: json['group_name']?.toString() ?? 'Savings group',
      payerUserId: _nonEmpty(json['payer_user_id']),
      payerName: json['payer_name']?.toString() ?? 'Member',
      matchStatus: json['match_status']?.toString() ?? 'manual_review',
      reason: json['reason']?.toString() ?? 'manual_review',
      amount: _asInt(json['amount']),
      createdAt: _parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt:
          _parseDateTime(json['updated_at']) ??
          _parseDateTime(json['created_at']) ??
          DateTime.now(),
      reference: _nonEmpty(json['matched_reference']),
      provider: _nonEmpty(json['provider']),
      payeeDigits: _nonEmpty(json['payee_digits']),
    );
  }
}

class BankAdminWorkspaceSnapshot {
  const BankAdminWorkspaceSnapshot({
    this.groups = const BankAdminPage<BankAdminGroupSummary>(),
    this.members = const BankAdminPage<BankAdminMemberRecord>(),
    this.contributions = const BankAdminPage<BankAdminContributionRecord>(),
    this.allocations = const BankAdminPage<BankAdminAllocationReviewItem>(),
  });

  final BankAdminPage<BankAdminGroupSummary> groups;
  final BankAdminPage<BankAdminMemberRecord> members;
  final BankAdminPage<BankAdminContributionRecord> contributions;
  final BankAdminPage<BankAdminAllocationReviewItem> allocations;

  bool get isEmpty =>
      groups.entries.isEmpty &&
      members.entries.isEmpty &&
      contributions.entries.isEmpty &&
      allocations.entries.isEmpty;
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
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

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
