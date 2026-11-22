import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const privacySubject = '99020000-0000-4000-8000-000000000001';
const privacyOtherSubject = '99020000-0000-4000-8000-000000000002';
const privacyOldSid = '99020000-0000-4000-8000-000000000101';
const privacyNewSid = '99020000-0000-4000-8000-000000000102';
const privacySubmission = '99020000-0000-4000-8000-000000004001';
const privacyCanonical = '99020000-0000-4000-8000-000000004002';

CollectAuthSession privacySession({
  String subject = privacySubject,
  String sid = privacyOldSid,
  String role = 'authenticated',
  int? exp,
  Object? claimSubject,
  Object? claimSid,
  Object? claimExpiration,
  String? refresh = 'SYNTHETIC_REFRESH',
  String phone = '+250788000001',
  bool anonymous = false,
}) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final claims = <String, Object?>{
    'sub': claimSubject ?? subject,
    'session_id': claimSid ?? sid,
    'role': role,
    'exp':
        claimExpiration ??
        exp ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  };
  return CollectAuthSession(
    accessToken:
        '${segment({'alg': 'SYNTHETIC'})}.${segment(claims)}.SYNTHETIC',
    refreshToken: refresh,
    tokenType: 'bearer',
    expiresIn: 3600,
    user: CollectAuthUser(
      id: subject,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
      phone: phone,
      role: 'authenticated',
      isAnonymous: anonymous,
    ),
  );
}

Map<String, dynamic> privacyReceiptJson({
  bool submission = false,
  String requestId = privacySubmission,
  String submissionId = privacySubmission,
  bool reasonSupplied = true,
  bool replay = false,
  bool equivalent = false,
}) => {
  'contract_version': 1,
  'request_id': requestId,
  'scope': 'own_account_eligible_data',
  'state': 'pending_review',
  'reason_code': 'account_deletion_requested',
  'reason_supplied': reasonSupplied,
  'accepted_at': '2026-10-02T00:00:00.000000Z',
  'policy_review_pending': true,
  'subject_scope_review_pending': true,
  'erasure_completed': false,
  'account_access_restricted': false,
  'auth_removed': false,
  'retention_approval_granted': false,
  'processor_operation_started': false,
  if (submission) ...{
    'submission_id': submissionId,
    'replay': replay,
    'equivalent_active_request': equivalent,
  },
};

/// Separate review observation; the immutable intake receipt stays unchanged.
Map<String, dynamic> privacyReviewJson({
  String requestId = privacyCanonical,
  String state = 'not_started',
  int? revision,
}) => {
  'contract_version': 1,
  'scope': 'own_account_privacy_review',
  'request_id': requestId,
  'checked_at': '2026-10-03T12:00:00.000000Z',
  'revision':
      revision ??
      (state == 'not_started' || state == 'awaiting_review'
          ? 0
          : state == 'blocked'
          ? 2
          : 1),
  'review_state': state,
  'outcome_code': state == 'blocked' ? 'policy_authority_unavailable' : null,
  'outcome_recorded_at': state == 'blocked'
      ? '2026-10-03T11:00:00.000000Z'
      : null,
  'completion': 'blocked',
  'blocking_reason': 'policy_authority_unavailable',
  'policy_acceptance_granted': false,
  'subject_scope_review_pending': true,
  'legal_hold_review_pending': true,
  'copy_dispositions_verified': false,
  'destructive_execution_available': false,
  'erasure_completed': false,
  'account_access_restricted': false,
  'auth_removed': false,
  'processor_operation_started': false,
};
