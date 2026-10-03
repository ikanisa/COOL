import '../../core/data/exact_json_values.dart';

/// Redacted, versioned operator approval evidence. Backend authority remains
/// responsible for current Auth verification, approval and role eligibility.
class AdminOperatorApproval {
  const AdminOperatorApproval._({
    required this.userId,
    required this.provider,
    required this.mode,
    required this.identityMasked,
    required this.approvedAt,
    required this.expiresAt,
    required this.status,
    required this.approved,
    required this.roleGranted,
    required this.adminAccess,
    required this.accessStatus,
  });

  final String userId, provider, mode, status, accessStatus;
  final String? identityMasked;
  final DateTime? approvedAt, expiresAt;
  final bool approved, roleGranted, adminAccess;

  bool get legacyControls => provider == 'whatsapp' && mode == 'transition';

  static AdminOperatorApproval parse(
    Map<String, dynamic> value, {
    required String targetUserId,
  }) {
    const fields = {
      'contract_version',
      'user_id',
      'provider',
      'mode',
      'identity_masked',
      'approved_at',
      'expires_at',
      'status',
      'approved',
      'role_granted',
      'admin_access',
      'access_status',
    };
    Never invalid() =>
        throw const FormatException('Invalid operator approval response.');
    if (value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        value['contract_version'] is! int ||
        value['contract_version'] != 1 ||
        value['user_id'] != targetUserId ||
        !RegExp(
          r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
        ).hasMatch(targetUserId) ||
        !{'email', 'whatsapp', 'unapproved'}.contains(value['provider']) ||
        !{'transition', 'email'}.contains(value['mode']) ||
        !{
          'approved',
          'not_approved',
          'revoked',
          'expired',
          'identity_changed',
          'pending_verification',
          'legacy_disabled',
        }.contains(value['status']) ||
        !{
          'active',
          'approval_required',
          'approved',
          'revoked',
        }.contains(value['access_status']) ||
        value['approved'] is! bool ||
        value['role_granted'] is! bool ||
        value['admin_access'] is! bool) {
      invalid();
    }
    final provider = value['provider'] as String;
    final mode = value['mode'] as String;
    final status = value['status'] as String;
    final approved = value['approved'] as bool;
    final granted = value['role_granted'] as bool;
    final masked = value['identity_masked'];
    if (masked != null &&
        (masked is! String ||
            masked.length > 128 ||
            (provider == 'email'
                ? !RegExp(r'^[^@\s]\*{3}@\*{3}$').hasMatch(masked)
                : provider != 'whatsapp' ||
                      !RegExp(r'^\+?[0-9*•… -]+$').hasMatch(masked) ||
                      !RegExp(r'[*•…]').hasMatch(masked)))) {
      invalid();
    }
    if ((provider == 'unapproved' && masked != null) ||
        (status == 'approved') != approved ||
        value['admin_access'] != (approved && granted) ||
        value['access_status'] !=
            (approved && granted
                ? 'active'
                : granted
                ? 'approval_required'
                : approved
                ? 'approved'
                : 'revoked') ||
        (approved &&
            (provider == 'unapproved' ||
                (provider == 'whatsapp' && mode != 'transition'))) ||
        (status == 'legacy_disabled' &&
            (provider != 'whatsapp' || mode != 'email')) ||
        (status == 'pending_verification' && provider != 'email')) {
      invalid();
    }
    DateTime? instant(String key) {
      if (value[key] == null) return null;
      if (value[key] is! String) invalid();
      return exactJsonTimestamp(value[key], field: key);
    }

    final approvedAt = instant('approved_at');
    final expiresAt = instant('expires_at');
    if ((approved && approvedAt == null) ||
        (expiresAt != null &&
            (approvedAt == null || !expiresAt.isAfter(approvedAt)))) {
      invalid();
    }
    return AdminOperatorApproval._(
      userId: targetUserId,
      provider: provider,
      mode: mode,
      identityMasked: masked as String?,
      approvedAt: approvedAt,
      expiresAt: expiresAt,
      status: status,
      approved: approved,
      roleGranted: granted,
      adminAccess: value['admin_access'] as bool,
      accessStatus: value['access_status'] as String,
    );
  }
}

bool adminOperatorApprovalReadMatches(
  String target,
  Map<String, dynamic> response,
) {
  try {
    AdminOperatorApproval.parse(response, targetUserId: target);
    return true;
  } on FormatException {
    return false;
  }
}
