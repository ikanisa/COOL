import 'privacy_contract.dart';

enum PrivacyReviewState {
  notStarted,
  awaitingReview,
  claimActive,
  claimExpired,
  blocked,
}

/// A subject-owned observation of review work, never an erasure receipt.
final class PrivacyReviewStatus {
  const PrivacyReviewStatus._({
    required this.requestId,
    required this.checkedAt,
    required this.revision,
    required this.state,
    required this.outcomeRecordedAt,
  });

  final String requestId;
  final DateTime checkedAt;
  final int revision;
  final PrivacyReviewState state;
  final DateTime? outcomeRecordedAt;

  static const _keys = {
    'contract_version',
    'scope',
    'request_id',
    'checked_at',
    'revision',
    'review_state',
    'outcome_code',
    'outcome_recorded_at',
    'completion',
    'blocking_reason',
    'policy_acceptance_granted',
    'subject_scope_review_pending',
    'legal_hold_review_pending',
    'copy_dispositions_verified',
    'destructive_execution_available',
    'erasure_completed',
    'account_access_restricted',
    'auth_removed',
    'processor_operation_started',
  };

  factory PrivacyReviewStatus.fromJson(Map<String, dynamic> json) {
    const states = {
      'not_started': PrivacyReviewState.notStarted,
      'awaiting_review': PrivacyReviewState.awaitingReview,
      'claim_active': PrivacyReviewState.claimActive,
      'claim_expired': PrivacyReviewState.claimExpired,
      'blocked': PrivacyReviewState.blocked,
    };
    final state = states[json['review_state']];
    final checked = _time(json['checked_at']);
    final recorded = _time(json['outcome_recorded_at']);
    final revision = json['revision'];
    final blocked = state == PrivacyReviewState.blocked;
    if (json.keys.toSet().difference(_keys).isNotEmpty ||
        _keys.difference(json.keys.toSet()).isNotEmpty ||
        json['contract_version'] is! int ||
        json['contract_version'] != 1 ||
        json['scope'] != 'own_account_privacy_review' ||
        !privacyUuid(json['request_id']) ||
        checked == null ||
        state == null ||
        revision is! int ||
        revision < 0 ||
        revision > 1000000000 ||
        ((state == PrivacyReviewState.notStarted ||
                state == PrivacyReviewState.awaitingReview) &&
            revision != 0) ||
        (state == PrivacyReviewState.blocked && revision < 2) ||
        (state != PrivacyReviewState.notStarted &&
            state != PrivacyReviewState.awaitingReview &&
            revision == 0) ||
        (blocked
            ? json['outcome_code'] != 'policy_authority_unavailable' ||
                  recorded == null ||
                  recorded.isAfter(checked)
            : json['outcome_code'] != null ||
                  json['outcome_recorded_at'] != null) ||
        json['completion'] != 'blocked' ||
        json['blocking_reason'] != 'policy_authority_unavailable' ||
        json['subject_scope_review_pending'] != true ||
        json['legal_hold_review_pending'] != true ||
        const [
          'policy_acceptance_granted',
          'copy_dispositions_verified',
          'destructive_execution_available',
          'erasure_completed',
          'account_access_restricted',
          'auth_removed',
          'processor_operation_started',
        ].any((key) => json[key] != false)) {
      throw const PrivacyRequestException(PrivacyFailure.protocolUnavailable);
    }
    return PrivacyReviewStatus._(
      requestId: json['request_id'] as String,
      checkedAt: checked,
      revision: revision,
      state: state,
      outcomeRecordedAt: recorded,
    );
  }

  static DateTime? _time(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
        ).hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.year < 1 || parsed.year > 9999) return null;
    var canonical = parsed.toUtc().toIso8601String();
    if (canonical.length == 24) canonical = '${canonical.substring(0, 23)}000Z';
    return canonical == value ? parsed : null;
  }

  @override
  String toString() => 'PrivacyReviewStatus(${state.name})';
}
