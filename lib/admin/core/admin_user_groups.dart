import '../../core/data/exact_json_values.dart';

final _userGroupUuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
final _userContribution = RegExp(
  r'^-?(?:0|[1-9][0-9]{0,17})(?:\.[0-9]{1,2})?$',
);

class AdminUserGroup {
  const AdminUserGroup._({
    required this.collectionId,
    required this.title,
    required this.visibility,
    required this.active,
    required this.roles,
    required this.membershipStatuses,
    required this.contributedAmountRwf,
    required this.contributionStatus,
  });
  final String collectionId, title, visibility, contributionStatus;
  final bool active;
  final List<String> roles, membershipStatuses;
  final String? contributedAmountRwf;

  factory AdminUserGroup.parse(Map<String, dynamic> json) {
    const keys = {
      'collection_id',
      'title',
      'visibility',
      'active',
      'roles',
      'membership_statuses',
      'contributed_amount_rwf',
      'contribution_status',
    };
    final roles = json['roles'];
    final statuses = json['membership_statuses'];
    final amount = json['contributed_amount_rwf'];
    bool strings(Object? values, Set<String> allowed, {bool empty = true}) =>
        values is List &&
        (empty || values.isNotEmpty) &&
        values.every((value) => value is String && allowed.contains(value)) &&
        values.toSet().length == values.length;
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['collection_id'] is! String ||
        !_userGroupUuid.hasMatch(json['collection_id'] as String) ||
        json['title'] is! String ||
        (json['title'] as String).trim().isEmpty ||
        !{
          'private',
          'public_requested',
          'public_approved',
          'public_rejected',
          'archived',
        }.contains(json['visibility']) ||
        json['active'] is! bool ||
        !strings(roles, {
          'owner',
          'admin',
          'member',
          'receiver',
          'contributor',
          'viewer',
        }, empty: false) ||
        !strings(statuses, {'active', 'invited', 'removed', 'left'}) ||
        !(json['contribution_status'] == 'unavailable' && amount == null ||
            json['contribution_status'] == 'available' &&
                amount is String &&
                _userContribution.hasMatch(amount))) {
      throw const FormatException('Invalid user group contribution response.');
    }
    return AdminUserGroup._(
      collectionId: json['collection_id'] as String,
      title: json['title'] as String,
      visibility: json['visibility'] as String,
      active: json['active'] as bool,
      roles: List<String>.unmodifiable((roles as List).cast<String>()),
      membershipStatuses: List<String>.unmodifiable(
        (statuses as List).cast<String>(),
      ),
      contributedAmountRwf: amount as String?,
      contributionStatus: json['contribution_status'] as String,
    );
  }
}

class AdminUserGroupsPage {
  const AdminUserGroupsPage._(this.userId, this.rows, this.total);
  final String userId;
  final List<AdminUserGroup> rows;
  final int total;

  factory AdminUserGroupsPage.parse(
    Map<String, dynamic> json, {
    required String userId,
    required int limit,
    required int offset,
  }) {
    final rows = json['rows'];
    final total = json['total'];
    if (json.length != 3 ||
        json['user_id'] != userId ||
        !_userGroupUuid.hasMatch(userId) ||
        rows is! List ||
        total is! int ||
        total < 0 ||
        total > maxExactJsonInteger ||
        limit < 1 ||
        limit > 100 ||
        offset < 0 ||
        offset > 2147483647) {
      throw const FormatException('Invalid user group page.');
    }
    final remaining = total - offset;
    if (rows.length != (remaining <= 0 ? 0 : remaining.clamp(0, limit))) {
      throw const FormatException('User group page is incomplete.');
    }
    final parsed = <AdminUserGroup>[];
    for (final row in rows) {
      if (row is! Map) throw const FormatException('Invalid user group.');
      parsed.add(AdminUserGroup.parse(Map<String, dynamic>.from(row)));
    }
    if (parsed.map((row) => row.collectionId).toSet().length != parsed.length) {
      throw const FormatException('Duplicate user group.');
    }
    return AdminUserGroupsPage._(userId, List.unmodifiable(parsed), total);
  }
}
