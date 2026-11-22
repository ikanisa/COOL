import 'dart:convert';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

void main() {
  test('reason matches PostgreSQL ordinary-space normalization', () {
    expect(cleanPrivacyReason(null), isNull);
    expect(cleanPrivacyReason('   '), isNull);
    expect(cleanPrivacyReason(' reason '), 'reason');
    expect(cleanPrivacyReason('\u00a0reason\u00a0'), '\u00a0reason\u00a0');
    expect(cleanPrivacyReason(List.filled(500, '🙂').join()), hasLength(1000));
  });
  for (final reason in [
    'a\nreason',
    'a\u0000reason',
    'a\u007freason',
    'a\u0085reason',
    List.filled(501, '🙂').join(),
  ]) {
    test('unsafe or oversized reason refused ${reason.length}', () {
      expect(
        () => cleanPrivacyReason(reason),
        throwsA(isA<PrivacyRequestException>()),
      );
    });
  }
  test('exact minimized pending receipt retains all unresolved semantics', () {
    final receipt = PrivacyIntakeReceipt.fromJson(
      privacyReceiptJson(),
      submission: false,
    );
    expect(receipt.acceptedAt, DateTime.utc(2026, 10, 2));
    expect(
      receipt.policyReviewPending && receipt.subjectScopeReviewPending,
      isTrue,
    );
    expect(
      receipt.erasureCompleted ||
          receipt.authRemoved ||
          receipt.retentionApprovalGranted ||
          receipt.processorOperationStarted ||
          receipt.accountAccessRestricted,
      isFalse,
    );
    expect(receipt.submissionId, isNull);
    expect(receipt.toString(), 'PrivacyIntakeReceipt(pending_review)');
  });
  final wrong = <String, Object?>{
    'contract_version': 1.0,
    'request_id': 'malformed',
    'scope': 'all_data',
    'state': 'completed',
    'reason_code': 'erased',
    'reason_supplied': 'true',
    'accepted_at': '2026-02-30T00:00:00.000000Z',
    'policy_review_pending': false,
    'subject_scope_review_pending': false,
    'erasure_completed': true,
    'account_access_restricted': true,
    'auth_removed': true,
    'retention_approval_granted': true,
    'processor_operation_started': true,
    'reason': 'PRIVATE_CANARY',
  };
  for (final entry in wrong.entries) {
    test('reject altered or private receipt field ${entry.key}', () {
      expect(
        () => PrivacyIntakeReceipt.fromJson({
          ...privacyReceiptJson(),
          entry.key: entry.value,
        }, submission: false),
        throwsA(isA<PrivacyRequestException>()),
      );
    });
  }
  test('missing pending field and submission fields in status refused', () {
    expect(
      () => PrivacyIntakeReceipt.fromJson(
        privacyReceiptJson()..remove('auth_removed'),
        submission: false,
      ),
      throwsA(isA<PrivacyRequestException>()),
    );
    expect(
      () => PrivacyIntakeReceipt.fromJson(
        privacyReceiptJson(submission: true),
        submission: false,
      ),
      throwsA(isA<PrivacyRequestException>()),
    );
  });
  test('equivalent canonical receipt and exact alias replay permitted', () {
    final receipt = PrivacyIntakeReceipt.fromJson(
      privacyReceiptJson(
        submission: true,
        requestId: privacyCanonical,
        replay: true,
        equivalent: true,
      ),
      submission: true,
    );
    expect(receipt.requestId, privacyCanonical);
    expect(receipt.submissionId, privacySubmission);
    expect(receipt.replay, isTrue);
  });
  test('inconsistent replay or alternate non-equivalent canonical refused', () {
    for (final json in [
      privacyReceiptJson(submission: true, replay: true),
      privacyReceiptJson(submission: true, requestId: privacyCanonical),
    ]) {
      expect(
        () => PrivacyIntakeReceipt.fromJson(json, submission: true),
        throwsA(isA<PrivacyRequestException>()),
      );
    }
  });
  test('identity codec is minimal and rejects private extras', () {
    final identity = PrivacyPendingIdentity(
      subjectId: privacySubject,
      submissionId: privacySubmission,
    );
    expect(
      identity.toJson().keys,
      unorderedEquals(['version', 'subject_id', 'submission_id']),
    );
    expect(
      PrivacyPendingIdentity.fromJson(
        jsonDecode(jsonEncode(identity.toJson())) as Map<String, dynamic>,
      ).submissionId,
      privacySubmission,
    );
    for (final extra in ['phone', 'reason', 'access_token', 'session_id']) {
      expect(
        () => PrivacyPendingIdentity.fromJson({
          ...identity.toJson(),
          extra: 'PRIVATE_CANARY',
        }),
        throwsA(isA<PrivacyRequestException>()),
      );
    }
  });
}
