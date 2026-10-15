import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

class CloudflareAdminAccountApi implements AdminAccountApi {
  CloudflareAdminAccountApi(this.session);
  final CloudflareAdminSession session;

  @override
  Future<void> signIn(String email, String password) =>
      session.signIn(email, password);

  Future<void> _mutation(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    final result = await session.request(
      path,
      body: body,
      authenticated: authenticated,
    );
    if (result['ok'] != true) {
      throw const AdminAccountException('The request was not confirmed.');
    }
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      _mutation('auth/forgot-password', {'email': email});

  @override
  Future<void> completePasswordSetup(
    String token,
    String password, {
    required bool invite,
  }) async {
    try {
      await _mutation('auth/complete-password', {
        'token': token,
        'password': password,
        'invite': invite,
      });
    } on CloudflareAdminRequestException catch (failure) {
      if (!failure.outcomeUnknown) rethrow;
      throw const AdminAccountSecurityOutcomeUnknown(
        'The password result is not confirmed. Sign in with the password you just chose. If it does not work, request a new reset email or ask the owner for a fresh invitation.',
      );
    }
    session.clear();
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      await _mutation('auth/change-password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }, authenticated: true);
    } on CloudflareAdminRequestException catch (failure) {
      if (!failure.outcomeUnknown) rethrow;
      throw const AdminAccountSecurityOutcomeUnknown(
        'The password result is not confirmed. Sign in with your new password. If it does not work, try your previous password. Request a reset email if neither works.',
      );
    }
    session.clear();
  }

  @override
  Future<AdminAccountTeam> loadTeam() async {
    final body = await session.request('team', authenticated: true);
    try {
      return AdminAccountTeam(
        currentEmail: body['currentEmail'] as String,
        canManage: body['canManage'] as bool,
        permissionsByRole: {
          for (final entry in (body['permissionsByRole'] as Map? ?? {}).entries)
            entry.key as String:
                const {'owner', 'admin', 'staff'}.contains(entry.key) &&
                    entry.value is List &&
                    (entry.value as List).every((value) => value is String)
                ? (entry.value as List).cast<String>()
                : throw const FormatException('Invalid access policy.'),
        },
        members: [
          for (final member in body['members'] as List)
            AdminAccountMember(
              id: member['id'] as String,
              email: member['email'] as String,
              role: AdminAccountRole.values.byName(member['role'] as String),
              status: AdminAccountStatus.values.byName(
                member['status'] as String,
              ),
              emailStatus: member['emailStatus'] as String?,
              publicId: member['publicId'] as String?,
              displayName: member['displayName'] as String?,
            ),
        ],
      );
    } catch (_) {
      throw const AdminAccountException('The team list could not be verified.');
    }
  }

  @override
  Future<void> invite(
    String email,
    AdminAccountRole role, {
    String displayName = '',
  }) => _mutation('team/invite', {
    'email': email,
    'role': role.name,
    'displayName': displayName,
  }, authenticated: true);

  @override
  Future<void> resendInvitation(String id) => _mutation(
    'team/${Uri.encodeComponent(id)}/resend',
    const {},
    authenticated: true,
  );

  @override
  Future<void> revokeMember(String id) => _mutation(
    'team/${Uri.encodeComponent(id)}/revoke',
    const {},
    authenticated: true,
  );
}
