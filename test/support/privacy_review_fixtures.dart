// Synthetic caller fixtures. SQL producer fixtures are reviewed separately;
// these values never represent a hosted review or approved deletion policy.
import 'dart:async';
import 'package:collect_app/admin/core/admin_privacy_review_models.dart';
import 'package:collect_app/admin/core/admin_privacy_review_checkpoint.dart';
import 'package:collect_app/admin/core/admin_privacy_review_sdk.dart';

const privacyActor = '99790000-0000-4000-8000-000000000001';
const privacySession = '99790000-0000-4000-8000-000000000002';
const privacyRequest = '99790000-0000-4000-8000-000000000003';
const privacyOperation = '99790000-0000-4000-8000-000000000004';
const privacyClaim = '99790000-0000-4000-8000-000000000005';
const privacyOutcomeOperation = '99790000-0000-4000-8000-000000000006';
final privacyNow = DateTime.parse('2026-10-03T12:00:00Z');
Map<String, dynamic> privacyEnvelope([DateTime? checked]) => {
  'contract_version': 1,
  'scope': 'account_privacy_review_only',
  'checked_at': (checked ?? privacyNow).toIso8601String(),
  'completion': 'blocked',
  'blocking_reason': 'policy_authority_unavailable',
  'policy_acceptance_granted': false,
  'destructive_execution_available': false,
  'erasure_completed': false,
  'account_access_restricted': false,
  'auth_removed': false,
  'processor_operation_started': false,
};
Map<String, dynamic> privacyItem({
  String id = privacyRequest,
  String state = 'not_started',
  DateTime? accepted,
  DateTime? expiry,
}) => {
  'request_id': id,
  'accepted_at': (accepted ?? privacyNow.subtract(const Duration(days: 1)))
      .toIso8601String(),
  'revision': state == 'blocked'
      ? 2
      : state == 'claim_active' || state == 'claim_expired'
      ? 1
      : 0,
  'review_state': state,
  'claim_expires_at':
      state == 'claim_active' || state == 'claim_expired' || state == 'blocked'
      ? (expiry ?? privacyNow.add(const Duration(seconds: 60)))
            .toIso8601String()
      : null,
  'outcome_code': state == 'blocked' ? 'policy_authority_unavailable' : null,
  'outcome_recorded_at': state == 'blocked'
      ? privacyNow.toIso8601String()
      : null,
};
Map<String, dynamic> privacyClaimReceipt({
  String operation = privacyOperation,
  DateTime? claimed,
}) {
  final at = claimed ?? privacyNow;
  return {
    'contract_version': 1,
    'scope': 'account_privacy_review_only',
    'request_id': privacyRequest,
    'claim_request_id': operation,
    'claim_id': privacyClaim,
    'revision': 1,
    'fence': 1,
    'claimed_at': at.toIso8601String(),
    'expires_at': at.add(const Duration(seconds: 60)).toIso8601String(),
    'policy_acceptance_granted': false,
    'destructive_execution_available': false,
    'erasure_completed': false,
  };
}

Map<String, dynamic> privacyOutcomeReceipt({
  String operation = privacyOutcomeOperation,
}) => {
  'contract_version': 1,
  'scope': 'account_privacy_review_only',
  'request_id': privacyRequest,
  'outcome_request_id': operation,
  'claim_id': privacyClaim,
  'revision': 2,
  'fence': 1,
  'outcome_code': 'policy_authority_unavailable',
  'recorded_at': privacyNow.toIso8601String(),
  'completion': 'blocked',
  'policy_acceptance_granted': false,
  'destructive_execution_available': false,
  'erasure_completed': false,
  'account_access_restricted': false,
  'auth_removed': false,
  'processor_operation_started': false,
};
Map<String, dynamic> privacyDetailRaw({
  String state = 'not_started',
  bool owned = false,
  DateTime? checked,
  DateTime? claimed,
  bool missing = false,
}) {
  final claim = claimed ?? privacyNow;
  return {
    ...privacyEnvelope(checked),
    'item': missing
        ? null
        : privacyItem(
            state: state,
            expiry: claim.add(const Duration(seconds: 60)),
          ),
    'own_claim_receipt': owned ? privacyClaimReceipt(claimed: claim) : null,
    'own_outcome_receipt': state == 'blocked' && owned
        ? privacyOutcomeReceipt()
        : null,
    'own_claim_authority_current': state == 'claim_active' && owned,
  };
}

AdminPrivacyReviewDetail privacyDetail({
  String state = 'not_started',
  bool owned = false,
  DateTime? checked,
  DateTime? claimed,
}) => AdminPrivacyReviewDetail.parse(
  privacyDetailRaw(
    state: state,
    owned: owned,
    checked: checked,
    claimed: claimed,
  ),
  privacyRequest,
);
Map<String, dynamic> privacyPageRaw({
  List<Map<String, dynamic>>? items,
  DateTime? checked,
  int limit = 25,
  Object? next,
}) => {
  ...privacyEnvelope(checked),
  'items': items ?? [privacyItem()],
  'limit': limit,
  'next_cursor': next,
};
Map<String, dynamic> privacyOperationRaw(
  AdminPrivacyReviewIntent intent, {
  bool observed = false,
  DateTime? checked,
  Object? receipt,
  bool current = false,
}) => {
  ...privacyEnvelope(checked),
  'operation_kind': intent.kind.name,
  'operation_id': intent.operationId,
  'observed': observed,
  'receipt': receipt,
  'claim_authority_current': current,
};
AdminPrivacyReviewIntent privacyIntent() => AdminPrivacyReviewIntent.claim(
  operationId: privacyOperation,
  actorId: privacyActor,
  sessionId: privacySession,
  detail: privacyDetail(),
);

class PrivacyJournalFixture {
  PrivacyJournalFixture({Map<String, String>? shared}) : bytes = shared ?? {} {
    store = AdminPrivacyReviewJournalStore(
      readRaw: (key) {
        if (failRead) throw StateError('storage refused');
        return bytes[key];
      },
      writeRaw: (key, value) {
        if (failWrite) throw StateError('quota');
        bytes[key] = value;
      },
      exclusive: (key, work) async {
        final previous = _tail, done = Completer<void>();
        _tail = done.future;
        await previous;
        try {
          work();
        } finally {
          done.complete();
        }
      },
    );
  }
  final Map<String, String> bytes;
  late final AdminPrivacyReviewStore store;
  bool failRead = false, failWrite = false;
  Future<void> _tail = Future.value();
}

class PrivacyApiFake implements AdminPrivacyReviewApi {
  AdminPrivacyReviewDetail sample = privacyDetail();
  DateTime checked = privacyNow;
  final writes = <AdminPrivacyReviewIntent>[];
  int reads = 0, lookups = 0;
  bool loseResponse = false, observed = false;
  Completer<Object>? deferredWrite;
  Completer<AdminPrivacyReviewPage>? deferredList;
  @override
  Future<AdminPrivacyReviewPage> list({
    int limit = 25,
    AdminPrivacyReviewCursor? before,
  }) async {
    reads++;
    if (deferredList != null) return deferredList!.future;
    return AdminPrivacyReviewPage.parse(
      privacyPageRaw(checked: checked, limit: limit),
      limit: limit,
      before: before,
    );
  }

  @override
  Future<AdminPrivacyReviewDetail> detail(String requestId) async {
    reads++;
    return sample;
  }

  Object receipt(AdminPrivacyReviewIntent intent) =>
      intent.kind == AdminPrivacyReviewOperationKind.claim
      ? AdminPrivacyReviewClaim.parse(
          privacyClaimReceipt(operation: intent.operationId),
        )
      : AdminPrivacyReviewOutcome.parse(
          privacyOutcomeReceipt(operation: intent.operationId),
        );
  @override
  Future<Object> write(
    AdminPrivacyReviewIntent intent,
    AdminPrivacyReviewDetail detail,
  ) async {
    writes.add(intent);
    if (deferredWrite != null) return deferredWrite!.future;
    if (loseResponse) {
      throw TimeoutException('Synthetic unknown write response');
    }
    sample = privacyDetail(
      state: intent.kind == AdminPrivacyReviewOperationKind.claim
          ? 'claim_active'
          : 'blocked',
      owned: true,
    );
    return receipt(intent);
  }

  @override
  Future<AdminPrivacyReviewOperation> resolve(
    AdminPrivacyReviewIntent intent,
  ) async {
    lookups++;
    return AdminPrivacyReviewOperation.parse(
      privacyOperationRaw(
        intent,
        checked: checked,
        observed: observed,
        receipt: !observed
            ? null
            : intent.kind == AdminPrivacyReviewOperationKind.claim
            ? privacyClaimReceipt(operation: intent.operationId)
            : privacyOutcomeReceipt(operation: intent.operationId),
        current:
            observed &&
            intent.kind == AdminPrivacyReviewOperationKind.claim &&
            sample.claimAuthorityCurrent,
      ),
      intent,
    );
  }
}
