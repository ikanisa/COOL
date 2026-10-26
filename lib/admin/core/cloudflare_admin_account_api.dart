import 'admin_account_api.dart';
import 'cloudflare_admin_session.dart';

class CloudflareAdminAccountApi
    implements
        AdminAccountApi,
        AdminEmailOtpAccountApi,
        AdminGoogleAccountApi,
        AdminInvitationV2AccountApi {
  CloudflareAdminAccountApi(this.session, {int invitationVersion = 2})
    : _invitationVersion = invitationVersion {
    if (!const {1, 2}.contains(invitationVersion)) {
      throw ArgumentError.value(invitationVersion, 'invitationVersion');
    }
  }
  final CloudflareAdminSession session;
  // Explicit v1 compatibility is for retained consumers/fixtures; it never
  // rewrites an existing intent's version or switches after an HTTP failure.
  final int _invitationVersion;
  @override
  bool get invitationV2Available =>
      invitationRecoveryAvailable && _invitationVersion == 2;

  @override
  bool get invitationRecoveryAvailable =>
      session.managedInvitationProtocolAvailable;
  @override
  Object get invitationAuthorityFence => session.authorityFence;
  @override
  bool get invitationManagementAuthorized {
    final user = session.user, now = DateTime.now();
    return invitationRecoveryAvailable &&
        user != null &&
        user.role == AdminAccountRole.owner &&
        user.email.toLowerCase() == 'info@ikanisa.com' &&
        user.permissions.contains('admin_users.manage') &&
        user.expiresAt.isAfter(now) &&
        user.hasRecentSensitiveVerification(now: now);
  }

  void _invitationAuthority(Object fence) {
    if (!invitationManagementAuthorized || fence != invitationAuthorityFence) {
      throw const AdminAccountException(
        'Verify your current owner sign-in before managing invitations.',
      );
    }
  }

  AdminInvitationReceipt _invitationReceipt(
    AdminInvitationIntent intent,
    Map<String, dynamic> value,
  ) {
    final receipt = AdminInvitationReceipt.parse(
      value,
      contractVersion: intent.contractVersion,
    );
    if (receipt.operation != intent.operation ||
        intent.staffId != null && receipt.staffId != intent.staffId ||
        intent.operation == AdminInvitationOperation.noticeRepair &&
            receipt.sourceRequestId != intent.priorRequestId) {
      throw const FormatException(
        'The original invitation could not be verified.',
      );
    }
    return receipt;
  }

  @override
  Future<AdminInvitationReceipt> submitInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  }) async {
    _invitationAuthority(authorityFence);
    try {
      final value = await session.request(
        intent.path,
        body: intent.body,
        authenticated: true,
        method: 'POST',
        idempotencyKey: intent.requestKey,
      );
      _invitationAuthority(authorityFence);
      final receipt = _invitationReceipt(intent, value);
      if (value['ok'] != true ||
          value['outcome'] != 'accepted' ||
          !receipt.message.accepted ||
          receipt.duplicate) {
        throw const FormatException('Unverified invitation result.');
      }
      return receipt;
    } on CloudflareAdminRequestException catch (failure) {
      _invitationAuthority(authorityFence);
      final typed = failure.invitationFailure;
      if (typed != null) {
        final receipt = typed.receipt;
        if (receipt != null &&
            (receipt.operation != intent.operation ||
                receipt.contractVersion != intent.contractVersion ||
                intent.staffId != null && receipt.staffId != intent.staffId ||
                intent.operation == AdminInvitationOperation.noticeRepair &&
                    receipt.sourceRequestId != intent.priorRequestId)) {
          throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
        }
        throw typed;
      }
      // An ordinary403 can follow committed preparation. No generic HTTP
      // status, parser failure or missing reference proves no operation.
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on FormatException {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on TypeError {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on ArgumentError {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    }
  }

  @override
  Future<AdminInvitationLookup> lookupInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  }) async {
    _invitationAuthority(authorityFence);
    try {
      final value = await session.request(
        intent.statusPath,
        authenticated: true,
        method: 'GET',
        idempotencyKey: intent.requestKey,
      );
      _invitationAuthority(authorityFence);
      if (value['ok'] != true) {
        throw const FormatException('Unverified invitation status.');
      }
      if (value['found'] == false &&
          (intent.contractVersion == 1
              ? value.length == 2
              : value.length == 3 &&
                    value['contractVersion'] is int &&
                    value['contractVersion'] == 2)) {
        return const AdminInvitationLookup.notFound();
      }
      if (value['found'] != true) {
        throw const FormatException('Unverified invitation status.');
      }
      return AdminInvitationLookup.found(_invitationReceipt(intent, value));
    } on CloudflareAdminRequestException {
      _invitationAuthority(authorityFence);
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on FormatException {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on TypeError {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } on ArgumentError {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    }
  }

  @override
  Future<void> signIn(String email, String password) =>
      session.signIn(email, password);

  @override
  Future<AdminEmailOtpReceipt> requestEmailOtp(String email) async {
    try {
      return await session.requestEmailOtp(email);
    } on CloudflareAdminRequestException catch (failure) {
      if (failure.code == 'admin_access_not_approved') {
        throw const AdminAccountAccessNotApproved();
      }
      rethrow;
    }
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    try {
      await session.verifyEmailOtp(
        email: email,
        challengeId: challengeId,
        code: code,
      );
    } on CloudflareAdminRequestException catch (failure) {
      if (failure.code == 'admin_access_not_approved') {
        throw const AdminAccountAccessNotApproved();
      }
      rethrow;
    }
  }

  @override
  bool get googleSignInAvailable => session.googleSignInAvailable;

  @override
  Future<void> signInWithGoogle({
    required AdminGoogleAuthorize authorize,
  }) async {
    try {
      await session.signInWithGoogle(authorize: authorize);
    } on CloudflareAdminRequestException catch (failure) {
      if (failure.code == 'admin_access_not_approved') {
        throw const AdminAccountAccessNotApproved();
      }
      rethrow;
    }
  }

  @override
  void cancelGoogleSignIn() => session.cancelGoogleSignIn();

  @override
  Future<bool> recheckSession() => session.recheckSession();

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
    final useV2 = invitationV2Available && invitationManagementAuthorized;
    final fence = invitationAuthorityFence;
    // Read-only consumers keep v1 visibility. Management still requires the
    // current Owner, grants and the backend-specific recent verification.
    final body = await session.request(
      useV2 ? 'team/v2' : 'team',
      authenticated: true,
    );
    try {
      if (useV2) {
        _invitationAuthority(fence);
        if (body['contractVersion'] is! int ||
            body['contractVersion'] != 2 ||
            body['currentEmail'] != session.user?.email ||
            body['canManage'] != true) {
          throw const FormatException(
            'Unverified team version or current owner.',
          );
        }
      }
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
              emailStatus: useV2 ? null : member['emailStatus'] as String?,
              publicId: member['publicId'] as String?,
              displayName: member['displayName'] as String?,
              invitation: useV2 ? _teamInvitationV2(member) : null,
              invitationRequestId: useV2
                  ? null
                  : _teamInvitationRequest(member),
              invitationOperation:
                  useV2 || member['invitationOperation'] == null
                  ? null
                  : AdminInvitationOperation.values.byName(
                      member['invitationOperation'] as String,
                    ),
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
  }) {
    if (invitationRecoveryAvailable) {
      throw const AdminAccountException(
        'Retain the original invitation before sending.',
      );
    }
    return _mutation('team/invite', {
      'email': email,
      'role': role.name,
      'displayName': displayName,
    }, authenticated: true);
  }

  @override
  Future<void> resendInvitation(String id) {
    if (invitationRecoveryAvailable) {
      throw const AdminAccountException(
        'Use the original invitation recovery flow.',
      );
    }
    return _mutation(
      'team/${Uri.encodeComponent(id)}/resend',
      const {},
      authenticated: true,
    );
  }

  String? _teamInvitationRequest(dynamic member) {
    final request = member['invitationRequestId'],
        operation = member['invitationOperation'];
    if (invitationRecoveryAvailable &&
        !const {
          null,
          'accepted',
          'rejected',
          'unknown',
          'already_registered',
        }.contains(member['emailStatus'])) {
      throw const FormatException('Unverified invitation history.');
    }
    if (request == null && operation == null) {
      if (invitationRecoveryAvailable && member['emailStatus'] != null) {
        throw const FormatException('Unverified invitation history.');
      }
      return null;
    }
    if (invitationRecoveryAvailable && member['emailStatus'] == null) {
      throw const FormatException('Unverified invitation history.');
    }
    if (!adminInvitationUuid(request) ||
        !const {'invite', 'resend'}.contains(operation)) {
      throw const FormatException('Unverified invitation history.');
    }
    return request as String;
  }

  AdminInvitationReceipt? _teamInvitationV2(dynamic member) {
    if (member is! Map ||
        !member.containsKey('invitation') ||
        member.containsKey('emailStatus') ||
        member.containsKey('noticeStatus') ||
        !adminInvitationUuid(member['id'])) {
      throw const FormatException('Unverified typed team invitation.');
    }
    if (member['invitation'] == null) return null;
    final value = member['invitation'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Unverified typed invitation.');
    }
    final receipt = AdminInvitationReceipt.parse(value, contractVersion: 2);
    if (receipt.staffId != member['id'] ||
        receipt.accessStatus.name != member['status']) {
      throw const FormatException('Team invitation target changed.');
    }
    return receipt;
  }

  @override
  Future<void> revokeMember(String id) => _mutation(
    'team/${Uri.encodeComponent(id)}/revoke',
    const {},
    authenticated: true,
  );
}
