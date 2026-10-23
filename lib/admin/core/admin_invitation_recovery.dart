import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';

const _family = 'team-invitation';
const _permission = 'admin_users.manage';
const _schema = AdminPendingAttemptSchema(
  fields: {
    'contract_version',
    'operation',
    'path',
    'staff_id',
    'prior_request_id',
    'prior_operation',
    'body',
  },
  nestedFields: {
    'body': {'email', 'role', 'displayName', 'sourceRequestId'},
  },
);

class AdminInvitationPending {
  AdminInvitationPending._(this.intent, {this.restored = false})
    : _submitted = restored;
  final AdminInvitationIntent intent;
  final bool restored;
  bool _submitted, _retryAllowed = false, _completed = false, _busy = false;
  AdminInvitationReceipt? _receipt;
  AdminInvitationOutcome? _outcome;
  AdminInvitationReceipt? get receipt => _receipt;
  AdminInvitationOutcome? get outcome => _outcome;
  bool get submitted => _submitted;
  bool get canRetry => _retryAllowed && !_completed && !_busy;
  bool get completed => _completed;
  bool get busy => _busy;
  String get message => canRetry
      ? outcome == AdminInvitationOutcome.transportUnavailable
            ? AdminInvitationFailure(outcome!, receipt: receipt).message
            : 'The original request was not found. Retry only the same invitation details.'
      : outcome != null
      ? AdminInvitationFailure(outcome!, receipt: receipt).message
      : receipt?.statusMessage ??
            'Check the original invitation before sending another.';
}

/// Same-tab recovery using the existing bounded authority-bound store. The
/// normalized email/name/role are necessary original business fields; browser
/// storage is plaintext sessionStorage, not a credential vault. Store binding,
/// eight-hour/session expiry, corruption handling and permission pruning stay
/// unchanged. No cross-logout key/body rediscovery is supplied by this protocol.
class AdminInvitationCoordinator {
  AdminInvitationCoordinator({
    required this.api,
    required this.store,
    required this.canManageTeam,
    String Function()? requestKey,
  }) : _fence = api.invitationAuthorityFence,
       _key = requestKey ?? (() => const Uuid().v4()) {
    if (api.invitationRecoveryAvailable &&
        api.invitationManagementAuthorized &&
        canManageTeam()) {
      _restore();
    }
  }
  final AdminInvitationAccountApi api;
  final AdminPendingAttemptStore store;
  final bool Function() canManageTeam;
  final Object _fence;
  final String Function() _key;
  final _attempts = <String, AdminInvitationPending>{};
  bool get usesV2 =>
      api is AdminInvitationV2AccountApi &&
      (api as AdminInvitationV2AccountApi).invitationV2Available;
  bool get isCurrent =>
      api.invitationRecoveryAvailable && api.invitationAuthorityFence == _fence;
  bool get authorized =>
      isCurrent && canManageTeam() && api.invitationManagementAuthorized;
  List<AdminInvitationPending> get pending => !isCurrent
      ? const []
      : List<AdminInvitationPending>.unmodifiable(
          _attempts.values.where((attempt) => !attempt.completed),
        );
  bool get hasPending => pending.isNotEmpty;

  void _owned(AdminInvitationPending? attempt) {
    if (!authorized ||
        attempt != null &&
            (_attempts[attempt.intent.resourceId] != attempt ||
                attempt.completed)) {
      throw const AdminAccountException(
        'Reopen team access with your current verified owner sign-in.',
      );
    }
  }

  bool canResend(AdminAccountMember member) =>
      authorized &&
      !hasPending &&
      member.role != AdminAccountRole.owner &&
      member.email.toLowerCase() != 'info@ikanisa.com' &&
      member.status == AdminAccountStatus.invited &&
      (member.invitation != null
          ? member.invitation!.message.accepted ||
                member.invitation!.message.rejected
          : const {'accepted', 'rejected'}.contains(member.emailStatus)) &&
      adminInvitationUuid(
        member.invitation?.requestId ?? member.invitationRequestId,
      ) &&
      (member.invitation?.operation ?? member.invitationOperation) != null;

  bool canRepairNotice(AdminAccountMember member) =>
      usesV2 &&
      authorized &&
      !hasPending &&
      member.role != AdminAccountRole.owner &&
      member.email.toLowerCase() != 'info@ikanisa.com' &&
      member.status != AdminAccountStatus.revoked &&
      (member.invitation?.emailStatus ==
              AdminInvitationEmailStatus.alreadyRegistered ||
          member.invitation == null &&
              member.emailStatus == 'already_registered') &&
      adminInvitationUuid(
        member.invitation?.requestId ?? member.invitationRequestId,
      ) &&
      const {
        AdminInvitationOperation.invite,
        AdminInvitationOperation.resend,
      }.contains(member.invitation?.operation ?? member.invitationOperation);

  AdminInvitationPending prepareInvite(
    String email,
    AdminAccountRole role, {
    String displayName = '',
  }) {
    _owned(null);
    if (hasPending) {
      throw const AdminAccountException(
        'Check the original invitation before starting another.',
      );
    }
    final intent = AdminInvitationIntent.invite(
      requestKey: _key(),
      email: email,
      role: role,
      displayName: displayName,
      contractVersion: usesV2 ? 2 : 1,
    );
    final attempt = AdminInvitationPending._(intent);
    _attempts[intent.resourceId] = attempt;
    return attempt;
  }

  AdminInvitationPending prepareResend(AdminAccountMember member) {
    _owned(null);
    if (!canResend(member)) {
      throw const AdminAccountException(
        'A new invitation requires a known accepted or rejected original request.',
      );
    }
    final intent = AdminInvitationIntent.resend(
      requestKey: _key(),
      staffId: member.id,
      priorRequestId:
          (member.invitation?.requestId ?? member.invitationRequestId)!,
      priorOperation:
          (member.invitation?.operation ?? member.invitationOperation)!,
      contractVersion: usesV2 ? 2 : 1,
    );
    final attempt = AdminInvitationPending._(intent);
    _attempts[intent.resourceId] = attempt;
    return attempt;
  }

  AdminInvitationPending prepareNoticeRepair(AdminAccountMember member) {
    _owned(null);
    if (!canRepairNotice(member)) {
      throw const AdminAccountException(
        'An access notice repair requires the original already-registered account request.',
      );
    }
    final intent = AdminInvitationIntent.noticeRepair(
      requestKey: _key(),
      staffId: member.id,
      sourceRequestId:
          (member.invitation?.requestId ?? member.invitationRequestId)!,
      sourceOperation:
          (member.invitation?.operation ?? member.invitationOperation)!,
    );
    final attempt = AdminInvitationPending._(intent);
    _attempts[intent.resourceId] = attempt;
    return attempt;
  }

  void _restore() {
    for (final saved in store.restoreFamily(
      family: _family,
      permission: _permission,
      schema: _schema,
    )) {
      final value = saved.intent, rawBody = value['body'];
      final version = value.containsKey('contract_version')
          ? value['contract_version'] == 2
                ? 2
                : throw const FormatException(
                    'Unverified retained invitation version.',
                  )
          : 1;
      if (rawBody is! Map<String, dynamic>) {
        throw const AdminAccountException(
          'The retained invitation needs an access review.',
        );
      }
      final AdminInvitationIntent intent;
      if (value['operation'] == 'invite') {
        if (rawBody['email'] is! String ||
            rawBody['role'] is! String ||
            rawBody['displayName'] is! String) {
          throw const AdminAccountException(
            'The retained invitation could not be verified.',
          );
        }
        intent = AdminInvitationIntent.invite(
          requestKey: saved.requestKey,
          email: rawBody['email'] as String,
          role: AdminAccountRole.values.byName(rawBody['role'] as String),
          displayName: rawBody['displayName'] as String,
          contractVersion: version,
        );
      } else if (value['operation'] == 'resend' &&
          value['staff_id'] is String &&
          value['prior_request_id'] is String &&
          value['prior_operation'] is String &&
          rawBody.isEmpty) {
        intent = AdminInvitationIntent.resend(
          requestKey: saved.requestKey,
          staffId: value['staff_id'] as String,
          priorRequestId: value['prior_request_id'] as String,
          priorOperation: adminInvitationOperation(value['prior_operation']),
          contractVersion: version,
        );
      } else if (version == 2 &&
          value['operation'] == 'notice_repair' &&
          value['staff_id'] is String &&
          value['prior_request_id'] is String &&
          value['prior_operation'] is String &&
          rawBody.length == 1 &&
          rawBody['sourceRequestId'] == value['prior_request_id']) {
        intent = AdminInvitationIntent.noticeRepair(
          requestKey: saved.requestKey,
          staffId: value['staff_id'] as String,
          sourceRequestId: value['prior_request_id'] as String,
          sourceOperation: adminInvitationOperation(value['prior_operation']),
        );
      } else {
        throw const AdminAccountException(
          'The retained invitation could not be verified.',
        );
      }
      if (saved.permission != _permission ||
          saved.resourceId != intent.resourceId ||
          jsonEncode(value) !=
              jsonEncode(_schema.canonical(intent.checkpoint))) {
        throw const AdminAccountException(
          'The retained invitation details changed.',
        );
      }
      _attempts[intent.resourceId] = AdminInvitationPending._(
        intent,
        restored: true,
      );
    }
    // Restoration is deliberately lookup-only: no POST, new key or guessed body.
  }

  void _retain(AdminInvitationPending attempt) {
    store.retain(
      family: _family,
      resourceId: attempt.intent.resourceId,
      requestKey: attempt.intent.requestKey,
      permission: _permission,
      intent: attempt.intent.checkpoint,
      schema: _schema,
    );
    if (!store.storageAvailable) {
      throw AdminAccountException(store.storageMessage);
    }
  }

  void _correlate(
    AdminInvitationPending attempt,
    AdminInvitationReceipt value,
  ) {
    final prior = attempt.receipt;
    if (value.contractVersion != attempt.intent.contractVersion ||
        value.operation != attempt.intent.operation ||
        attempt.intent.staffId != null &&
            value.staffId != attempt.intent.staffId ||
        attempt.intent.operation == AdminInvitationOperation.noticeRepair &&
            value.sourceRequestId != attempt.intent.priorRequestId ||
        prior != null &&
            (prior.staffId != value.staffId ||
                prior.requestId != value.requestId ||
                prior.messageKind != value.messageKind ||
                prior.sourceRequestId != value.sourceRequestId)) {
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    }
    attempt._receipt = value;
  }

  void _settle(AdminInvitationPending attempt, AdminInvitationReceipt receipt) {
    _owned(attempt);
    _correlate(attempt, receipt);
    if (!receipt.terminal) return;
    final saved = store.restore(
      family: _family,
      resourceId: attempt.intent.resourceId,
      schema: _schema,
    );
    if (saved == null ||
        saved.requestKey != attempt.intent.requestKey ||
        jsonEncode(saved.intent) !=
            jsonEncode(_schema.canonical(attempt.intent.checkpoint))) {
      throw const AdminAccountException(
        'The original checkpoint could not be verified.',
      );
    }
    store.clear(family: _family, resourceId: attempt.intent.resourceId);
    attempt._completed = true;
  }

  Future<AdminInvitationReceipt> submit(
    AdminInvitationPending attempt, {
    bool confirmedSameIntentRetry = false,
  }) async {
    _owned(attempt);
    if (attempt._busy ||
        attempt._submitted &&
            (!attempt.canRetry || !confirmedSameIntentRetry)) {
      throw const AdminAccountException(
        'Check the original request before explicitly retrying the same details.',
      );
    }
    _retain(attempt); // Successful storage write AND readback precede POST.
    attempt._busy = true;
    attempt._submitted = true;
    attempt._retryAllowed = false;
    try {
      final receipt = await api.submitInvitation(
        attempt.intent,
        authorityFence: _fence,
      );
      _owned(attempt);
      if (!receipt.message.accepted || receipt.duplicate) {
        throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
      }
      attempt._outcome = null;
      _settle(attempt, receipt);
      return receipt;
    } on AdminInvitationFailure catch (failure) {
      _owned(attempt);
      attempt._outcome = failure.outcome;
      if (failure.receipt != null) {
        _correlate(attempt, failure.receipt!);
        if (failure.outcome == AdminInvitationOutcome.transportUnavailable) {
          // Only the exact definite no-claim POST evidence enables this retry.
          // It is not reconstructed from a metadata-only unknown GET/reload.
          attempt._retryAllowed = true;
        }
        // A duplicate409 always requires the exact original GET, including a
        // duplicate carrying an older accepted result. It is not a new send.
        if (failure.outcome != AdminInvitationOutcome.existingRequest &&
            failure.outcome != AdminInvitationOutcome.operationUnknown) {
          _settle(attempt, failure.receipt!);
        }
      }
      rethrow;
    } catch (_) {
      _owned(attempt);
      attempt._outcome = AdminInvitationOutcome.operationUnknown;
      throw AdminInvitationFailure(AdminInvitationOutcome.operationUnknown);
    } finally {
      attempt._busy = false;
    }
  }

  Future<AdminInvitationLookup> lookup(AdminInvitationPending attempt) async {
    _owned(attempt);
    if (attempt._busy) {
      throw const AdminAccountException('Wait for the original request check.');
    }
    attempt._busy = true;
    attempt._retryAllowed = false;
    try {
      final result = await api.lookupInvitation(
        attempt.intent,
        authorityFence: _fence,
      );
      _owned(attempt);
      if (!result.found) {
        // No automatic retry or new intent is created by this read result.
        attempt._retryAllowed = true;
        return result;
      }
      final receipt = result.receipt!;
      _correlate(attempt, receipt);
      attempt._outcome = !receipt.terminal
          ? AdminInvitationOutcome.deliveryUnknown
          : null;
      _settle(attempt, receipt);
      return result;
    } catch (_) {
      _owned(attempt);
      attempt._outcome = AdminInvitationOutcome.operationUnknown;
      throw AdminInvitationFailure(
        AdminInvitationOutcome.operationUnknown,
        receipt: attempt.receipt,
      );
    } finally {
      attempt._busy = false;
    }
  }
}
