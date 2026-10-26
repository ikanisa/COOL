import 'dart:convert';

enum PrivacyFailure {
  sessionChanged,
  busy,
  cancelled,
  codeRequired,
  invalidCode,
  phoneUnavailable,
  captchaRequired,
  rateLimited,
  verificationUnavailable,
  freshSignInRequired,
  invalidReason,
  conflictingRequest,
  requestUnavailable,
  submissionLimit,
  outcomeUnknown,
  protocolUnavailable,
}

/// Public errors contain only fixed codes, never provider bodies or credentials.
final class PrivacyRequestException implements Exception {
  const PrivacyRequestException(this.failure);
  final PrivacyFailure failure;
  @override
  String toString() => 'PrivacyRequestException(${failure.name})';
}

bool privacyUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);

String? cleanPrivacyReason(String? reason) {
  if (reason == null) return null;
  if (reason.runes.length > 500 ||
      utf8.encode(reason).length > 2000 ||
      reason.runes.any((rune) => rune < 32 || (rune >= 127 && rune <= 159))) {
    throw const PrivacyRequestException(PrivacyFailure.invalidReason);
  }
  // PostgreSQL btrim(text) removes ordinary spaces, not every Unicode space.
  final clean = reason.replaceAll(RegExp(r'^ +| +$'), '');
  return clean.isEmpty ? null : clean;
}

/// The only permitted checkpoint fields. A checkpoint never authorizes a write.
final class PrivacyPendingIdentity {
  PrivacyPendingIdentity({
    required this.subjectId,
    required this.submissionId,
  }) {
    if (!privacyUuid(subjectId) || !privacyUuid(submissionId)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
  }
  final String subjectId;
  final String submissionId;

  factory PrivacyPendingIdentity.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        json['version'] is! int ||
        json['version'] != 1 ||
        !privacyUuid(json['subject_id']) ||
        !privacyUuid(json['submission_id'])) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    return PrivacyPendingIdentity(
      subjectId: json['subject_id'] as String,
      submissionId: json['submission_id'] as String,
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'subject_id': subjectId,
    'submission_id': submissionId,
  };
  @override
  String toString() => 'PrivacyPendingIdentity';
}

/// A server-confirmed intake receipt. It does not represent account erasure.
final class PrivacyIntakeReceipt {
  const PrivacyIntakeReceipt._({
    required this.requestId,
    required this.reasonSupplied,
    required this.acceptedAt,
    this.submissionId,
    this.replay,
    this.equivalentActiveRequest,
  });

  final String requestId;
  final bool reasonSupplied;
  final DateTime acceptedAt;
  final String? submissionId;
  final bool? replay;
  final bool? equivalentActiveRequest;
  String get state => 'pending_review';
  bool get policyReviewPending => true;
  bool get subjectScopeReviewPending => true;
  bool get erasureCompleted => false;
  bool get accountAccessRestricted => false;
  bool get authRemoved => false;
  bool get retentionApprovalGranted => false;
  bool get processorOperationStarted => false;

  static const _baseKeys = {
    'contract_version',
    'request_id',
    'scope',
    'state',
    'reason_code',
    'reason_supplied',
    'accepted_at',
    'policy_review_pending',
    'subject_scope_review_pending',
    'erasure_completed',
    'account_access_restricted',
    'auth_removed',
    'retention_approval_granted',
    'processor_operation_started',
  };

  factory PrivacyIntakeReceipt.fromJson(
    Map<String, dynamic> json, {
    required bool submission,
  }) {
    final keys = {
      ..._baseKeys,
      if (submission) ...{
        'submission_id',
        'replay',
        'equivalent_active_request',
      },
    };
    final time = json['accepted_at'];
    DateTime? accepted;
    if (time is String &&
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
        ).hasMatch(time)) {
      accepted = DateTime.tryParse(time);
      var canonical = accepted?.toUtc().toIso8601String();
      if (canonical != null && canonical.length == 24) {
        canonical = '${canonical.substring(0, 23)}000Z';
      }
      if (canonical != time) accepted = null;
    }
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['contract_version'] is! int ||
        json['contract_version'] != 1 ||
        !privacyUuid(json['request_id']) ||
        json['scope'] != 'own_account_eligible_data' ||
        json['state'] != 'pending_review' ||
        json['reason_code'] != 'account_deletion_requested' ||
        json['reason_supplied'] is! bool ||
        accepted == null ||
        json['policy_review_pending'] != true ||
        json['subject_scope_review_pending'] != true ||
        json['erasure_completed'] != false ||
        json['account_access_restricted'] != false ||
        json['auth_removed'] != false ||
        json['retention_approval_granted'] != false ||
        json['processor_operation_started'] != false ||
        (submission &&
            (!privacyUuid(json['submission_id']) ||
                json['replay'] is! bool ||
                json['equivalent_active_request'] is! bool ||
                (json['replay'] == true &&
                    json['equivalent_active_request'] != true) ||
                (json['equivalent_active_request'] == false &&
                    json['request_id'] != json['submission_id'])))) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    return PrivacyIntakeReceipt._(
      requestId: json['request_id'] as String,
      reasonSupplied: json['reason_supplied'] as bool,
      acceptedAt: accepted,
      submissionId: submission ? json['submission_id'] as String : null,
      replay: submission ? json['replay'] as bool : null,
      equivalentActiveRequest: submission
          ? json['equivalent_active_request'] as bool
          : null,
    );
  }
  @override
  String toString() => 'PrivacyIntakeReceipt(pending_review)';
}
