import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

const privacySubject = '99020000-0000-4000-8000-000000000001';
const privacyOtherSubject = '99020000-0000-4000-8000-000000000002';
const privacyOldSid = '99020000-0000-4000-8000-000000000101';
const privacyNewSid = '99020000-0000-4000-8000-000000000102';
const privacySubmission = '99020000-0000-4000-8000-000000004001';
const privacyCanonical = '99020000-0000-4000-8000-000000004002';

Session privacySession({
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
  return Session(
    accessToken:
        '${segment({'alg': 'SYNTHETIC'})}.${segment(claims)}.SYNTHETIC',
    refreshToken: refresh,
    tokenType: 'bearer',
    expiresIn: 3600,
    user: User(
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
