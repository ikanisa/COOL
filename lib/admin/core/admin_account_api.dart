import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Account operations are authorised and completed by the account service.
/// A successful email request confirms acceptance for sending, not delivery.
abstract interface class AdminAccountApi {
  Future<void> signIn(String email, String password);
  Future<void> requestPasswordReset(String email);
  Future<void> completePasswordSetup(
    String token,
    String password, {
    required bool invite,
  });
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<AdminAccountTeam> loadTeam();
  Future<void> invite(
    String email,
    AdminAccountRole role, {
    String displayName = '',
  });
  Future<void> resendInvitation(String id);
  Future<void> revokeMember(String id);
}

final adminAccountApiProvider = Provider<AdminAccountApi>((ref) {
  throw const AdminAccountException(
    'Account access is not configured. Contact your administrator.',
  );
});

class AdminAccountException implements Exception {
  const AdminAccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A response may be lost after the credential transaction commits. Recover by
/// authenticating, rather than replaying a one-use link or password mutation.
class AdminAccountSecurityOutcomeUnknown extends AdminAccountException {
  const AdminAccountSecurityOutcomeUnknown(super.message);
}

enum AdminAccountRole {
  owner('Owner'),
  admin('Admin'),
  staff('Staff');

  const AdminAccountRole(this.label);
  final String label;
}

enum AdminAccountStatus {
  active('Active'),
  invited('Invitation pending'),
  revoked('Access removed');

  const AdminAccountStatus(this.label);
  final String label;
}

class AdminAccountMember {
  const AdminAccountMember({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    this.emailStatus,
    this.publicId,
    this.displayName,
  });
  final String id;
  final String email;
  final AdminAccountRole role;
  final AdminAccountStatus status;

  /// The latest server-observed email request status; never proof of delivery.
  final String? emailStatus;
  final String? publicId;
  final String? displayName;
}

class AdminAccountTeam {
  const AdminAccountTeam({
    required this.members,
    required this.currentEmail,
    required this.canManage,
    this.permissionsByRole = const {},
  });
  final Map<String, List<String>> permissionsByRole;
  final List<AdminAccountMember> members;
  final String currentEmail;
  final bool canManage;
}
