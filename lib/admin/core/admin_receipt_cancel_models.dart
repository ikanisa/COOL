import '../../core/data/exact_json_values.dart';

Never cancelInvalid() => throw const FormatException(
  'Receipt cancellation evidence could not be validated.',
);
Map<String, dynamic> cancelObject(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((key) => key is! String || !keys.contains(key))) {
    cancelInvalid();
  }
  return Map<String, dynamic>.from(raw);
}

String cancelUuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    cancelInvalid();
  }
  return raw;
}

int cancelRevision(Object? raw, {int maximum = 1000000000}) => exactJsonInteger(
  raw,
  field: 'receipt revision',
  minimum: 1,
  maximum: maximum,
);
DateTime cancelInstant(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    cancelInvalid();
  }
  final value = exactJsonTimestamp(raw, field: 'receipt action time');
  final canonical =
      '${value.toIso8601String().split('.').first}.${value.millisecond.toString().padLeft(3, '0')}${value.microsecond.toString().padLeft(3, '0')}Z';
  if (canonical != raw) cancelInvalid();
  return value;
}

void _version(Map<String, dynamic> row) {
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != 'rw_receipt_manual_cancel') {
    cancelInvalid();
  }
}

bool _fresh(DateTime checkedAt, DateTime validUntil, DateTime now) =>
    !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
void _ttl(DateTime checkedAt, DateTime until) {
  if (until.difference(checkedAt) != const Duration(seconds: 60)) {
    cancelInvalid();
  }
}

enum AdminReceiptCancelReason {
  operatorCancelled('operator_cancelled', 'Operator cancellation'),
  recipientReviewRequired(
    'recipient_review_required',
    'Recipient review required',
  ),
  contentReviewRequired('content_review_required', 'Content review required');

  const AdminReceiptCancelReason(this.wire, this.label);
  final String wire, label;
  static AdminReceiptCancelReason parse(Object? raw) =>
      values.firstWhere((value) => value.wire == raw, orElse: cancelInvalid);
}

enum AdminReceiptCancelEligibility {
  eligible('eligible', 'Eligible: queued with no recorded transport history'),
  stateNotQueued('state_not_queued', 'Blocked: receipt is not queued'),
  priorTransportEvidence(
    'prior_transport_evidence',
    'Blocked: prior claim or transport evidence exists',
  ),
  sourceEvidenceInvalid(
    'source_evidence_invalid',
    'Blocked: immutable payment or receipt evidence does not qualify',
  ),
  alreadyCancelled(
    'already_cancelled',
    'Blocked: this receipt was already cancelled',
  ),
  revisionExhausted(
    'revision_exhausted',
    'Blocked: receipt revision limit reached',
  );

  const AdminReceiptCancelEligibility(this.wire, this.label);
  final String wire, label;
  static AdminReceiptCancelEligibility parse(Object? raw) =>
      values.firstWhere((value) => value.wire == raw, orElse: cancelInvalid);
}

class AdminReceiptCancelInspection {
  const AdminReceiptCancelInspection._(
    this.outboxId,
    this.checkedAt,
    this.validUntil,
    this.revision,
    this.state,
    this.eligibility,
  );
  final String outboxId;
  final DateTime checkedAt, validUntil;
  final int? revision;
  final String? state;
  final AdminReceiptCancelEligibility? eligibility;
  bool get available => revision != null;
  bool get canCancel => eligibility == AdminReceiptCancelEligibility.eligible;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminReceiptCancelInspection.parse(
    Object? raw, {
    required String outboxId,
  }) {
    cancelUuid(outboxId);
    final row = cancelObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'outbox_id',
      'status',
      'receipt',
    });
    _version(row);
    final checked = cancelInstant(row['checked_at']),
        until = cancelInstant(row['sample_valid_until']);
    _ttl(checked, until);
    if (row['outbox_id'] != outboxId ||
        !{'available', 'unavailable'}.contains(row['status'])) {
      cancelInvalid();
    }
    if (row['status'] == 'unavailable') {
      if (row['receipt'] != null) cancelInvalid();
      return AdminReceiptCancelInspection._(
        outboxId,
        checked,
        until,
        null,
        null,
        null,
      );
    }
    final receipt = cancelObject(row['receipt'], {
      'outbox_id',
      'revision',
      'state',
      'can_cancel',
      'reason_code',
    });
    final revision = cancelRevision(receipt['revision']),
        state = receipt['state'];
    final reason = AdminReceiptCancelEligibility.parse(receipt['reason_code']);
    if (receipt['outbox_id'] != outboxId ||
        !{
          'queued',
          'awaiting_confirmation',
          'send_started',
          'observed_sent',
          'failed_no_send',
          'uncertain',
          'suppressed',
        }.contains(state) ||
        receipt['can_cancel'] is! bool ||
        receipt['can_cancel'] !=
            (reason == AdminReceiptCancelEligibility.eligible)) {
      cancelInvalid();
    }
    if ((revision == 1000000000) !=
            (reason == AdminReceiptCancelEligibility.revisionExhausted) ||
        reason == AdminReceiptCancelEligibility.alreadyCancelled &&
            state != 'suppressed' ||
        reason == AdminReceiptCancelEligibility.stateNotQueued &&
            state == 'queued' ||
        {
              AdminReceiptCancelEligibility.eligible,
              AdminReceiptCancelEligibility.priorTransportEvidence,
              AdminReceiptCancelEligibility.sourceEvidenceInvalid,
            }.contains(reason) &&
            state != 'queued') {
      cancelInvalid();
    }
    return AdminReceiptCancelInspection._(
      outboxId,
      checked,
      until,
      revision,
      state as String,
      reason,
    );
  }
}

class AdminReceiptCancelIntent {
  AdminReceiptCancelIntent({
    required String requestId,
    required String outboxId,
    required Object revision,
    required this.reason,
  }) : requestId = cancelUuid(requestId),
       outboxId = cancelUuid(outboxId),
       revision = cancelRevision(revision, maximum: 999999999);
  final String requestId, outboxId;
  final int revision;
  final AdminReceiptCancelReason reason;
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_outbox_id': outboxId,
    'p_expected_revision': revision,
    'p_reason_code': reason.wire,
  });
  factory AdminReceiptCancelIntent.fromParameters(Object? raw) {
    final row = cancelObject(raw, {
      'p_request_id',
      'p_outbox_id',
      'p_expected_revision',
      'p_reason_code',
    });
    return AdminReceiptCancelIntent(
      requestId: cancelUuid(row['p_request_id']),
      outboxId: cancelUuid(row['p_outbox_id']),
      revision: cancelRevision(row['p_expected_revision'], maximum: 999999999),
      reason: AdminReceiptCancelReason.parse(row['p_reason_code']),
    );
  }
}

class AdminReceiptCancelReceipt {
  const AdminReceiptCancelReceipt._(
    this.requestId,
    this.outboxId,
    this.expectedRevision,
    this.revision,
    this.reason,
    this.recordedAt,
  );
  final String requestId, outboxId;
  final int expectedRevision, revision;
  final AdminReceiptCancelReason reason;
  final DateTime recordedAt;
  bool matches(AdminReceiptCancelIntent intent) =>
      requestId == intent.requestId &&
      outboxId == intent.outboxId &&
      expectedRevision == intent.revision &&
      reason == intent.reason;
  factory AdminReceiptCancelReceipt.parse(
    Object? raw, {
    AdminReceiptCancelIntent? intent,
  }) {
    final row = cancelObject(raw, {
      'contract_version',
      'scope',
      'request_id',
      'outbox_id',
      'expected_revision',
      'revision',
      'action',
      'reason_code',
      'recorded_at',
      'state_before',
      'state_after',
      'financial_action',
      'send_action',
      'provider_delivery_verified',
      'primary_receipt_retained',
    });
    _version(row);
    final expected = cancelRevision(
          row['expected_revision'],
          maximum: 999999999,
        ),
        revision = cancelRevision(row['revision']);
    if (revision != expected + 1 ||
        row['action'] != 'cancel_unstarted' ||
        row['state_before'] != 'queued' ||
        row['state_after'] != 'suppressed' ||
        row['financial_action'] != false ||
        row['send_action'] != false ||
        row['provider_delivery_verified'] != false ||
        row['primary_receipt_retained'] != true) {
      cancelInvalid();
    }
    final result = AdminReceiptCancelReceipt._(
      cancelUuid(row['request_id']),
      cancelUuid(row['outbox_id']),
      expected,
      revision,
      AdminReceiptCancelReason.parse(row['reason_code']),
      cancelInstant(row['recorded_at']),
    );
    if (intent != null && !result.matches(intent)) cancelInvalid();
    return result;
  }
}

class AdminReceiptCancelLookup {
  const AdminReceiptCancelLookup._(
    this.requestId,
    this.checkedAt,
    this.validUntil,
    this.status,
    this.receipt,
  );
  final String requestId, status;
  final DateTime checkedAt, validUntil;
  final AdminReceiptCancelReceipt? receipt;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminReceiptCancelLookup.parse(
    Object? raw, {
    required String requestId,
  }) {
    cancelUuid(requestId);
    final row = cancelObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'request_id',
      'status',
      'receipt',
    });
    _version(row);
    final checked = cancelInstant(row['checked_at']),
        until = cancelInstant(row['sample_valid_until']);
    _ttl(checked, until);
    if (row['request_id'] != requestId ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(row['status'])) {
      cancelInvalid();
    }
    final receipt = row['status'] == 'recorded'
        ? AdminReceiptCancelReceipt.parse(row['receipt'])
        : null;
    if (receipt != null &&
            (receipt.requestId != requestId ||
                receipt.recordedAt.isAfter(checked)) ||
        receipt == null && row['receipt'] != null) {
      cancelInvalid();
    }
    return AdminReceiptCancelLookup._(
      requestId,
      checked,
      until,
      row['status'] as String,
      receipt,
    );
  }
}
