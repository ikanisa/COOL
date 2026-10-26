import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_email_otp.dart';

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

/// The current Admin entry flow verifies an owner-approved email address.
/// Password operations remain available for previously issued recovery links.
abstract interface class AdminEmailOtpAccountApi {
  Future<AdminEmailOtpReceipt> requestEmailOtp(String email);
  Future<void> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String code,
  });
}

/// Optional browser-only Google capability. Existing account implementations
/// keep their current email/password contract without implementing this seam.
typedef AdminGoogleAuthorize =
    Future<Map<String, dynamic>> Function(
      Future<Uri> Function(String? returnOrigin) createUrl,
      String state,
      String callbackOrigin,
    );

abstract interface class AdminGoogleAccountApi {
  bool get googleSignInAvailable;
  Future<void> signInWithGoogle({required AdminGoogleAuthorize authorize});
  void cancelGoogleSignIn();

  /// One explicit cookie-session read. False means confirmed signed out;
  /// an unavailable or superseded read throws and must keep fresh auth locked.
  Future<bool> recheckSession();
}

class AdminEmailOtpReceipt {
  const AdminEmailOtpReceipt({
    required this.challengeId,
    required this.retryAfterSeconds,
    required this.expiresInSeconds,
  });
  final String challengeId;
  final int retryAfterSeconds;
  final int expiresInSeconds;
}

class AdminAccountAccessNotApproved extends AdminAccountException {
  const AdminAccountAccessNotApproved()
    : super('This email does not have Admin access. Contact your super admin.');
}

class AdminEmailOtpDeliveryUnknown extends AdminAccountException {
  const AdminEmailOtpDeliveryUnknown(this.receipt)
    : super(
        'Email delivery could not be confirmed. If a code arrives, enter it before requesting another.',
      );
  final AdminEmailOtpReceipt receipt;
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
    this.invitationRequestId,
    this.invitationOperation,
    this.invitation,
  });
  final String id;
  final String email;
  final AdminAccountRole role;
  final AdminAccountStatus status;

  /// The latest server-observed email request status; never proof of delivery.
  final String? emailStatus;
  final String? publicId;
  final String? displayName;
  final String? invitationRequestId;
  final AdminInvitationOperation? invitationOperation;

  /// Discriminated v2 history. A notice never populates emailStatus.
  final AdminInvitationReceipt? invitation;
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

/// Optional managed-invitation protocol. Existing account/OTP implementations
/// keep their contracts; only a supported team flow uses this recovery seam.
abstract interface class AdminInvitationAccountApi {
  bool get invitationRecoveryAvailable;
  bool get invitationManagementAuthorized;
  Object get invitationAuthorityFence;
  Future<AdminInvitationReceipt> submitInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  });
  Future<AdminInvitationLookup> lookupInvitation(
    AdminInvitationIntent intent, {
    required Object authorityFence,
  });
}

abstract interface class AdminInvitationV2AccountApi
    implements AdminInvitationAccountApi {
  bool get invitationV2Available;
}

enum AdminInvitationOperation {
  invite('invite'),
  resend('resend'),
  noticeRepair('notice_repair');

  const AdminInvitationOperation(this.wireName);
  final String wireName;
}

AdminInvitationOperation adminInvitationOperation(Object? value) =>
    switch (value) {
      'invite' => AdminInvitationOperation.invite,
      'resend' => AdminInvitationOperation.resend,
      'notice_repair' => AdminInvitationOperation.noticeRepair,
      _ => throw const FormatException('Unverified invitation operation.'),
    };

enum AdminInvitationEmailStatus {
  accepted,
  rejected,
  unknown,
  alreadyRegistered,
}

enum AdminAccessNoticeStatus { accepted, rejected, unknown }

enum AdminInvitationMessageKind { authInvite, accessNotice }

sealed class AdminInvitationMessage {
  const AdminInvitationMessage();
  bool get accepted;
  bool get rejected;
  bool get terminal;
  String get statusMessage;
}

final class AdminNativeInvitationMessage extends AdminInvitationMessage {
  const AdminNativeInvitationMessage(this.emailStatus);
  final AdminInvitationEmailStatus emailStatus;
  @override
  bool get accepted => emailStatus == AdminInvitationEmailStatus.accepted;
  @override
  bool get rejected => emailStatus == AdminInvitationEmailStatus.rejected;
  @override
  bool get terminal => emailStatus != AdminInvitationEmailStatus.unknown;
  @override
  String get statusMessage => switch (emailStatus) {
    AdminInvitationEmailStatus.accepted =>
      'Original invitation accepted for sending. Inbox delivery is not confirmed.',
    AdminInvitationEmailStatus.rejected => 'Invitation request rejected.',
    AdminInvitationEmailStatus.unknown =>
      'Invitation sending is unconfirmed. Check the original request.',
    AdminInvitationEmailStatus.alreadyRegistered =>
      'Account already registered. Check linked Admin access. No invitation email was sent.',
  };
}

final class AdminAccessNoticeMessage extends AdminInvitationMessage {
  const AdminAccessNoticeMessage(this.noticeStatus);
  final AdminAccessNoticeStatus noticeStatus;
  @override
  bool get accepted => noticeStatus == AdminAccessNoticeStatus.accepted;
  @override
  bool get rejected => noticeStatus == AdminAccessNoticeStatus.rejected;
  @override
  bool get terminal => noticeStatus != AdminAccessNoticeStatus.unknown;
  @override
  String get statusMessage => switch (noticeStatus) {
    AdminAccessNoticeStatus.accepted =>
      'Original access notice accepted for sending. Inbox delivery and sign-in are not confirmed.',
    AdminAccessNoticeStatus.rejected => 'Access notice sending was rejected.',
    AdminAccessNoticeStatus.unknown =>
      'Access notice sending is unconfirmed. Check the original request.',
  };
}

enum AdminInvitationOutcome {
  operationUnknown,
  deliveryUnknown,
  deliveryRejected,
  notificationPending,
  existingRequest,
  transportUnavailable,
}

bool adminInvitationUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

/// Original normalized business fields only. The client key is never replaced
/// by the separate server request UUID. No credential is part of this intent.
class AdminInvitationIntent {
  AdminInvitationIntent._(
    this.requestKey,
    this.operation,
    this.staffId,
    this.priorRequestId,
    this.priorOperation,
    Map<String, dynamic> body,
    this.contractVersion,
  ) : body = Map<String, dynamic>.unmodifiable(body) {
    if (!const {1, 2}.contains(contractVersion) ||
        !RegExp(r'^[A-Za-z0-9._:-]{8,200}$').hasMatch(requestKey)) {
      throw const FormatException('Invalid original invitation reference.');
    }
  }
  factory AdminInvitationIntent.invite({
    required String requestKey,
    required String email,
    required AdminAccountRole role,
    String displayName = '',
    int contractVersion = 1,
  }) {
    final target = normalizeAdminEmail(email), name = displayName.trim();
    if (target == 'info@ikanisa.com' ||
        role == AdminAccountRole.owner ||
        name.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException('Check the invitation details.');
    }
    return AdminInvitationIntent._(
      requestKey,
      AdminInvitationOperation.invite,
      null,
      null,
      null,
      {'email': target, 'role': role.name, 'displayName': name},
      contractVersion,
    );
  }
  factory AdminInvitationIntent.resend({
    required String requestKey,
    required String staffId,
    required String priorRequestId,
    required AdminInvitationOperation priorOperation,
    int contractVersion = 1,
  }) {
    if (!adminInvitationUuid(staffId) ||
        !adminInvitationUuid(priorRequestId) ||
        contractVersion == 1 &&
            priorOperation == AdminInvitationOperation.noticeRepair) {
      throw const FormatException('Check the original invitation history.');
    }
    return AdminInvitationIntent._(
      requestKey,
      AdminInvitationOperation.resend,
      staffId,
      priorRequestId,
      priorOperation,
      const {},
      contractVersion,
    );
  }
  factory AdminInvitationIntent.noticeRepair({
    required String requestKey,
    required String staffId,
    required String sourceRequestId,
    required AdminInvitationOperation sourceOperation,
  }) {
    if (!adminInvitationUuid(staffId) ||
        !adminInvitationUuid(sourceRequestId) ||
        sourceOperation == AdminInvitationOperation.noticeRepair) {
      throw const FormatException(
        'Check the original registered-account request.',
      );
    }
    return AdminInvitationIntent._(
      requestKey,
      AdminInvitationOperation.noticeRepair,
      staffId,
      sourceRequestId,
      sourceOperation,
      {'sourceRequestId': sourceRequestId},
      2,
    );
  }
  final String requestKey;
  final int contractVersion;
  final AdminInvitationOperation operation;
  final String? staffId, priorRequestId;
  final AdminInvitationOperation? priorOperation;
  final Map<String, dynamic> body;
  String get _prefix => contractVersion == 2 ? 'team/v2' : 'team';
  String get statusPath => '$_prefix/invitation-status';
  String get path => switch (operation) {
    AdminInvitationOperation.invite => '$_prefix/invite',
    AdminInvitationOperation.resend => '$_prefix/$staffId/resend',
    AdminInvitationOperation.noticeRepair => '$_prefix/$staffId/access-notice',
  };
  String get resourceId => contractVersion == 1
      ? operation == AdminInvitationOperation.invite
            ? 'invite'
            : 'resend:$staffId'
      : operation == AdminInvitationOperation.invite
      ? 'v2:invite'
      : operation == AdminInvitationOperation.resend
      ? 'v2:resend:$staffId'
      : 'v2:notice_repair:$staffId:$priorRequestId';
  Map<String, dynamic> get checkpoint => {
    if (contractVersion == 2) 'contract_version': 2,
    'operation': operation.wireName,
    'path': path,
    'staff_id': staffId,
    'prior_request_id': priorRequestId,
    'prior_operation': priorOperation?.wireName,
    'body': body,
  };
}

class AdminInvitationReceipt {
  const AdminInvitationReceipt({
    required this.staffId,
    required this.requestId,
    required AdminInvitationEmailStatus this.emailStatus,
    required this.accessStatus,
    required this.operation,
    required this.replayed,
    required this.duplicate,
    this.contractVersion = 1,
    this.sourceRequestId,
  }) : noticeStatus = null;
  const AdminInvitationReceipt.notice({
    required this.staffId,
    required this.requestId,
    required AdminAccessNoticeStatus this.noticeStatus,
    required this.accessStatus,
    required this.operation,
    required this.replayed,
    required this.duplicate,
    this.sourceRequestId,
  }) : emailStatus = null,
       contractVersion = 2;
  final String staffId, requestId;
  final int contractVersion;
  final String? sourceRequestId;
  final AdminInvitationEmailStatus? emailStatus;
  final AdminAccessNoticeStatus? noticeStatus;
  final AdminAccountStatus accessStatus;
  final AdminInvitationOperation operation;
  final bool replayed, duplicate;
  AdminInvitationMessageKind get messageKind => noticeStatus == null
      ? AdminInvitationMessageKind.authInvite
      : AdminInvitationMessageKind.accessNotice;
  AdminInvitationMessage get message => noticeStatus == null
      ? AdminNativeInvitationMessage(emailStatus!)
      : AdminAccessNoticeMessage(noticeStatus!);
  bool get terminal => message.terminal;
  String get statusMessage => message.statusMessage;
  factory AdminInvitationReceipt.parse(
    Map<String, dynamic> value, {
    int contractVersion = 1,
  }) {
    if (!const {1, 2}.contains(contractVersion) ||
        !adminInvitationUuid(value['id']) ||
        !adminInvitationUuid(value['requestId']) ||
        value['replayed'] is! bool ||
        value['duplicate'] is! bool) {
      throw const FormatException(
        'Invitation references could not be verified.',
      );
    }
    final operation = adminInvitationOperation(value['operation']);
    final access = AdminAccountStatus.values.byName(
      value['accessStatus'] as String,
    );
    if (contractVersion == 1) {
      if (operation == AdminInvitationOperation.noticeRepair ||
          const {
            'contractVersion',
            'messageKind',
            'noticeStatus',
            'sourceRequestId',
          }.any(value.containsKey)) {
        throw const FormatException('Use the original invitation version.');
      }
    } else if (value['contractVersion'] is! int ||
        value['contractVersion'] != 2 ||
        !value.containsKey('sourceRequestId') ||
        value['sourceRequestId'] != null &&
            !adminInvitationUuid(value['sourceRequestId'])) {
      throw const FormatException('Unverified invitation version or lineage.');
    }
    final kind = contractVersion == 1 ? 'auth_invite' : value['messageKind'];
    if (kind == 'access_notice' &&
        !value.containsKey('emailStatus') &&
        value.containsKey('noticeStatus')) {
      final notice = switch (value['noticeStatus']) {
        'accepted' => AdminAccessNoticeStatus.accepted,
        'rejected' => AdminAccessNoticeStatus.rejected,
        'unknown' => AdminAccessNoticeStatus.unknown,
        _ => throw const FormatException(
          'Access notice sending is unverified.',
        ),
      };
      if (operation == AdminInvitationOperation.noticeRepair &&
          value['sourceRequestId'] == null) {
        throw const FormatException('Missing original repair lineage.');
      }
      return AdminInvitationReceipt.notice(
        staffId: value['id'] as String,
        requestId: value['requestId'] as String,
        noticeStatus: notice,
        accessStatus: access,
        operation: operation,
        replayed: value['replayed'] as bool,
        duplicate: value['duplicate'] as bool,
        sourceRequestId: value['sourceRequestId'] as String?,
      );
    }
    if (kind != 'auth_invite' ||
        value.containsKey('noticeStatus') ||
        operation == AdminInvitationOperation.noticeRepair) {
      throw const FormatException(
        'Invitation message kind could not be verified.',
      );
    }
    final email = switch (value['emailStatus']) {
      'accepted' => AdminInvitationEmailStatus.accepted,
      'rejected' => AdminInvitationEmailStatus.rejected,
      'unknown' => AdminInvitationEmailStatus.unknown,
      'already_registered' => AdminInvitationEmailStatus.alreadyRegistered,
      _ => throw const FormatException('Invitation sending is unverified.'),
    };
    return AdminInvitationReceipt(
      staffId: value['id'] as String,
      requestId: value['requestId'] as String,
      emailStatus: email,
      accessStatus: access,
      operation: operation,
      replayed: value['replayed'] as bool,
      duplicate: value['duplicate'] as bool,
      contractVersion: contractVersion,
      sourceRequestId: value['sourceRequestId'] as String?,
    );
  }
}

class AdminInvitationLookup {
  const AdminInvitationLookup.notFound() : receipt = null;
  const AdminInvitationLookup.found(AdminInvitationReceipt value)
    : receipt = value;
  final AdminInvitationReceipt? receipt;
  bool get found => receipt != null;
}

class AdminInvitationFailure extends AdminAccountException {
  AdminInvitationFailure(this.outcome, {this.receipt})
    : super(switch (outcome) {
        AdminInvitationOutcome.operationUnknown =>
          'The invitation result is unknown. Keep the original request and check its status.',
        AdminInvitationOutcome.deliveryUnknown =>
          receipt?.messageKind == AdminInvitationMessageKind.accessNotice
              ? 'Access notice sending is unconfirmed. Check the original request before sending another.'
              : 'Invitation sending is unconfirmed. Check the original request before sending another.',
        AdminInvitationOutcome.deliveryRejected =>
          receipt?.messageKind == AdminInvitationMessageKind.accessNotice
              ? 'Access notice sending was rejected.'
              : 'Invitation request rejected.',
        AdminInvitationOutcome.notificationPending =>
          'Account already registered. Check linked Admin access. No invitation email was sent.',
        AdminInvitationOutcome.existingRequest =>
          'An invitation request already exists. Check the original request.',
        AdminInvitationOutcome.transportUnavailable =>
          'Access notice sending is unavailable. No send was started. Retry only this same request after configuration.',
      });
  final AdminInvitationOutcome outcome;
  final AdminInvitationReceipt? receipt;
}

/// Only exact version/path-specific evidence can describe a known send result.
/// Arbitrary provider messages, mixed native/notice fields and incompatible
/// receipt versions remain operationUnknown in the actual request adapter.
AdminInvitationFailure? parseAdminInvitationFailure(
  Map<String, dynamic> value,
  int status, {
  int contractVersion = 1,
}) {
  try {
    final error = value['error'];
    if (value['ok'] != false || error is! Map) return null;
    final outcome = switch ((status, value['outcome'], error['code'])) {
      (503, 'operation_unknown', 'invitation_operation_unknown') =>
        AdminInvitationOutcome.operationUnknown,
      (503, 'delivery_unknown', 'invitation_delivery_unknown') =>
        AdminInvitationOutcome.deliveryUnknown,
      (422, 'delivery_rejected', 'invitation_rejected') =>
        AdminInvitationOutcome.deliveryRejected,
      (409, 'notification_pending', 'invitation_notification_required') =>
        AdminInvitationOutcome.notificationPending,
      (409, 'existing_request', 'invitation_existing_request') =>
        AdminInvitationOutcome.existingRequest,
      (503, 'transport_unavailable', 'invitation_transport_unavailable')
          when contractVersion == 2 =>
        AdminInvitationOutcome.transportUnavailable,
      _ => null,
    };
    if (outcome == null) return null;
    const fields = {
      'id',
      'requestId',
      'emailStatus',
      'noticeStatus',
      'accessStatus',
      'operation',
      'replayed',
      'duplicate',
      'contractVersion',
      'messageKind',
      'sourceRequestId',
    };
    final receipt = fields.any(value.containsKey)
        ? AdminInvitationReceipt.parse(value, contractVersion: contractVersion)
        : null;
    if (receipt == null && outcome != AdminInvitationOutcome.operationUnknown) {
      return null;
    }
    if (receipt != null) {
      final valid = switch (outcome) {
        AdminInvitationOutcome.operationUnknown => !receipt.terminal,
        AdminInvitationOutcome.deliveryUnknown =>
          !receipt.terminal && !receipt.duplicate,
        AdminInvitationOutcome.deliveryRejected =>
          receipt.message.rejected && !receipt.duplicate,
        AdminInvitationOutcome.notificationPending =>
          receipt.emailStatus == AdminInvitationEmailStatus.alreadyRegistered &&
              !receipt.duplicate,
        AdminInvitationOutcome.existingRequest => receipt.duplicate,
        AdminInvitationOutcome.transportUnavailable =>
          receipt.messageKind == AdminInvitationMessageKind.accessNotice &&
              !receipt.terminal &&
              !receipt.duplicate,
      };
      if (!valid) return null;
    }
    return AdminInvitationFailure(outcome, receipt: receipt);
  } catch (_) {
    return null;
  }
}
