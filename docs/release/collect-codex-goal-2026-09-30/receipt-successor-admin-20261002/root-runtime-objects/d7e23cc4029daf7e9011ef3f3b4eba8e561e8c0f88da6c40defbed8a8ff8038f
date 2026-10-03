import '../../core/data/exact_json_values.dart';

Never exceptionInvalid() =>
    throw const FormatException('Invalid operational exception evidence.');

Map<String, dynamic> exceptionObject(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    exceptionInvalid();
  }
  return Map<String, dynamic>.from(value);
}

String exceptionUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    exceptionInvalid();
  }
  return value;
}

DateTime exceptionInstant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
      ).hasMatch(value)) {
    exceptionInvalid();
  }
  return exactJsonTimestamp(value, field: 'exception time');
}

int _revision(Object? value) {
  if (value is! int || value < 1 || value > 1000000000) exceptionInvalid();
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) exceptionInvalid();
  return value;
}

bool _fresh(DateTime checked, DateTime until, DateTime now) =>
    !checked.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
    now.toUtc().isBefore(until);

enum AdminExceptionSource {
  rawSms('raw_sms', 'Payment message'),
  allocation('allocation', 'Allocation'),
  payment('payment', 'Payment'),
  receipt('receipt', 'SMS receipt'),
  gateway('gateway', 'SMS Gateway'),
  receiptEvent('receipt_event', 'Receipt event'),
  receiptBacklog('receipt_backlog', 'Receipt backlog'),
  receiptTelemetry('receipt_telemetry', 'Receipt telemetry');

  const AdminExceptionSource(this.wire, this.label);
  final String wire, label;
  bool get isReceiptDeferral => this == receiptEvent || this == receiptBacklog;
  static AdminExceptionSource parse(Object? value) =>
      values.firstWhere((item) => item.wire == value, orElse: exceptionInvalid);
}

enum AdminExceptionAction {
  acknowledge('acknowledge', 'Acknowledge'),
  escalate('escalate', 'Request escalation');

  const AdminExceptionAction(this.wire, this.label);
  final String wire, label;
  static AdminExceptionAction parse(Object? value) =>
      values.firstWhere((item) => item.wire == value, orElse: exceptionInvalid);
}

enum AdminExceptionReviewReason {
  reviewStarted('review_started', 'Review started'),
  ownerReviewRequired('owner_review_required', 'Owner review required'),
  uncertainSendReview('uncertain_send_review', 'Uncertain send review'),
  contactReview('contact_review', 'Contact review');

  const AdminExceptionReviewReason(this.wire, this.label);
  final String wire, label;
  static AdminExceptionReviewReason parse(Object? value) =>
      values.firstWhere((item) => item.wire == value, orElse: exceptionInvalid);
}

const _reasons = <String, (AdminExceptionSource, String)>{
  'TELEMETRY_BACKLOG_AGED': (
    AdminExceptionSource.receiptTelemetry,
    'Receipt backlog age',
  ),
  'TELEMETRY_HANDLING_LATENCY_HIGH': (
    AdminExceptionSource.receiptTelemetry,
    'Durable handling latency',
  ),
  'TELEMETRY_ACTION_BUDGET_EXHAUSTED': (
    AdminExceptionSource.receiptTelemetry,
    'Action budget exhausted',
  ),
  'TELEMETRY_SMS_BUDGET_EXHAUSTED': (
    AdminExceptionSource.receiptTelemetry,
    'SMS segment budget exhausted',
  ),
  'TELEMETRY_DELIVERY_CALLBACK_GAP': (
    AdminExceptionSource.receiptTelemetry,
    'Callback observation gap',
  ),
  'TELEMETRY_SEND_OUTCOME_UNKNOWN': (
    AdminExceptionSource.receiptTelemetry,
    'Unknown send outcome',
  ),
  'PARSING_FAILED': (AdminExceptionSource.rawSms, 'Message parsing failed'),
  'ALLOCATION_REVIEW': (
    AdminExceptionSource.allocation,
    'Allocation needs review',
  ),
  'VERIFICATION_PENDING': (
    AdminExceptionSource.payment,
    'Verification pending',
  ),
  'VERIFICATION_REJECTED': (
    AdminExceptionSource.payment,
    'Verification rejected',
  ),
  'VERIFICATION_CONFLICT': (
    AdminExceptionSource.payment,
    'Verification conflict',
  ),
  'CONTACT_MISSING': (AdminExceptionSource.payment, 'Receipt contact missing'),
  'SEND_UNCERTAIN': (AdminExceptionSource.receipt, 'Send outcome uncertain'),
  'SEND_FAILED_NO_SEND': (
    AdminExceptionSource.receipt,
    'Definite failure before send',
  ),
  'RECEIPT_SUPPRESSED': (AdminExceptionSource.receipt, 'Receipt suppressed'),
  'GATEWAY_UNOBSERVED': (
    AdminExceptionSource.gateway,
    'Gateway report missing',
  ),
  'GATEWAY_STALE': (AdminExceptionSource.gateway, 'Gateway report expired'),
  'GATEWAY_SMS_PERMISSION': (
    AdminExceptionSource.gateway,
    'Gateway SMS permission denied',
  ),
  'GATEWAY_NETWORK': (
    AdminExceptionSource.gateway,
    'Gateway network needs review',
  ),
  'GATEWAY_TELEPHONY': (
    AdminExceptionSource.gateway,
    'Gateway telephony needs review',
  ),
  'GATEWAY_SIM': (AdminExceptionSource.gateway, 'Gateway SIM not selected'),
};

const adminReceiptDeferralLabels = <String, String>{
  'SOURCE_CHANGED': 'Receipt source changed',
  'SOURCE_BUSY': 'Receipt source is busy',
  'PAYMENT_NOT_POSTED': 'Payment is not posted',
  'SNAPSHOT_MISSING': 'Receipt balance snapshot missing',
  'RECIPIENT_INELIGIBLE': 'Receipt recipient is ineligible',
  'POLICY_DISABLED': 'Receipt policy disabled',
  'CONSENT_MISSING': 'Receipt consent missing',
  'CONTACT_MISSING': 'Receipt contact missing',
  'CONTACT_HISTORY_UNPROVEN': 'Historical receipt contact unverified',
  'POLICY_HISTORY_UNPROVEN': 'Historical receipt policy unverified',
  'CONSENT_HISTORY_UNPROVEN': 'Historical receipt consent unverified',
  'CATCHUP_DISABLED': 'Receipt catch-up disabled',
  'CATCHUP_WINDOW_EXCEEDED': 'Receipt catch-up window exceeded',
  'CONTENT_REFUSED': 'Receipt wording refused',
  'LEGACY_CONTENT_REVIEW_REQUIRED': 'Earlier receipt wording needs review',
  'QUOTA_EXHAUSTED': 'Receipt operating limit exhausted',
};

String? adminExceptionReasonLabel(AdminExceptionSource source, String code) {
  if (source.isReceiptDeferral && code.startsWith('RECEIPT_OPERATION_')) {
    return adminReceiptDeferralLabels[code.substring(
      'RECEIPT_OPERATION_'.length,
    )];
  }
  final legacy = _reasons[code];
  return legacy?.$1 == source ? legacy?.$2 : null;
}

class AdminExceptionRow {
  const AdminExceptionRow._(
    this.id,
    this.source,
    this.sourceId,
    this.reasonCode,
    this.active,
    this.revision,
    this.sourceSha256,
    this.firstObservedAt,
    this.lastChangedAt,
    this.transactionSmsId,
    this.acknowledged,
    this.escalationRequested,
  );
  final String id, sourceId, reasonCode, sourceSha256;
  final AdminExceptionSource source;
  final bool active, acknowledged, escalationRequested;
  final int revision;
  final DateTime firstObservedAt, lastChangedAt;
  final String? transactionSmsId;
  String get reasonLabel => adminExceptionReasonLabel(source, reasonCode)!;
  String? get investigationPath => transactionSmsId != null
      ? '/admin/transactions/momo:$transactionSmsId'
      : source == AdminExceptionSource.receipt
      ? '/admin/sms-receipts/$sourceId'
      : source == AdminExceptionSource.gateway
      ? '/admin/sms-gateway'
      : null;
  String get investigationLabel => source == AdminExceptionSource.receipt
      ? 'Open SMS receipt'
      : source == AdminExceptionSource.gateway
      ? 'Open SMS Gateway'
      : 'Open transaction';
  factory AdminExceptionRow.parse(Object? value, DateTime checked) {
    final data = exceptionObject(value, {
      'id',
      'source_kind',
      'source_id',
      'reason_code',
      'active',
      'revision',
      'source_sha256',
      'first_observed_at',
      'last_changed_at',
      'transaction_sms_id',
      'acknowledged',
      'escalation_requested',
    });
    final source = AdminExceptionSource.parse(data['source_kind']);
    final reason = data['reason_code'];
    if (reason is! String ||
        adminExceptionReasonLabel(source, reason) == null ||
        data['source_sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['source_sha256'] as String)) {
      exceptionInvalid();
    }
    final sourceId = exceptionUuid(data['source_id']);
    final sms = data['transaction_sms_id'] == null
        ? null
        : exceptionUuid(data['transaction_sms_id']);
    if ((source == AdminExceptionSource.receipt ||
                source == AdminExceptionSource.gateway ||
                source == AdminExceptionSource.receiptTelemetry) &&
            sms != null ||
        source == AdminExceptionSource.rawSms &&
            sms != null &&
            sms != sourceId) {
      exceptionInvalid();
    }
    final first = exceptionInstant(data['first_observed_at']);
    final last = exceptionInstant(data['last_changed_at']);
    if (first.isAfter(last) || last.isAfter(checked)) exceptionInvalid();
    return AdminExceptionRow._(
      exceptionUuid(data['id']),
      source,
      sourceId,
      reason,
      _boolean(data['active']),
      _revision(data['revision']),
      data['source_sha256'] as String,
      first,
      last,
      sms,
      _boolean(data['acknowledged']),
      _boolean(data['escalation_requested']),
    );
  }
}

class AdminExceptionCursor {
  const AdminExceptionCursor(this.changedAt, this.id);
  final DateTime changedAt;
  final String id;
  factory AdminExceptionCursor.parse(Object? value) {
    final data = exceptionObject(value, {'changed_at', 'id'});
    return AdminExceptionCursor(
      exceptionInstant(data['changed_at']),
      exceptionUuid(data['id']),
    );
  }
}

class AdminExceptionSnapshot {
  const AdminExceptionSnapshot._(
    this.checkedAt,
    this.validUntil,
    this.rows,
    this.nextCursor,
  );
  final DateTime checkedAt, validUntil;
  final List<AdminExceptionRow> rows;
  final AdminExceptionCursor? nextCursor;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminExceptionSnapshot.parse(
    Map<String, dynamic> raw, {
    required bool active,
    required int limit,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) {
    final data = exceptionObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'active',
      'source_kind',
      'limit',
      'rows',
      'next_cursor',
      'escalation_delivery_verified',
      'source_scan_complete',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 2 ||
        data['scope'] != 'platform_global' ||
        data['active'] is! bool ||
        data['active'] != active ||
        data['source_kind'] != source?.wire ||
        data['limit'] is! int ||
        data['limit'] != limit ||
        limit < 1 ||
        limit > 50 ||
        (beforeChangedAt == null) != (beforeId == null) ||
        data['escalation_delivery_verified'] != false ||
        data['source_scan_complete'] != false) {
      exceptionInvalid();
    }
    if (beforeId != null) exceptionUuid(beforeId);
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60) ||
        data['rows'] is! List) {
      exceptionInvalid();
    }
    final rows = (data['rows'] as List)
        .map((row) => AdminExceptionRow.parse(row, checked))
        .toList(growable: false);
    if (rows.length > limit ||
        rows.any(
          (row) =>
              row.active != active || source != null && row.source != source,
        ) ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      exceptionInvalid();
    }
    var previous = beforeChangedAt == null
        ? null
        : AdminExceptionCursor(beforeChangedAt.toUtc(), beforeId!);
    for (final row in rows) {
      if (previous != null &&
          (row.lastChangedAt.isAfter(previous.changedAt) ||
              row.lastChangedAt == previous.changedAt &&
                  row.id.compareTo(previous.id) >= 0)) {
        exceptionInvalid();
      }
      previous = AdminExceptionCursor(row.lastChangedAt, row.id);
    }
    final cursor = data['next_cursor'] == null
        ? null
        : AdminExceptionCursor.parse(data['next_cursor']);
    if (cursor != null &&
        (rows.length != limit ||
            cursor.changedAt != rows.last.lastChangedAt ||
            cursor.id != rows.last.id)) {
      exceptionInvalid();
    }
    return AdminExceptionSnapshot._(
      checked,
      until,
      List.unmodifiable(rows),
      cursor,
    );
  }
}

class AdminExceptionIntent {
  AdminExceptionIntent({
    required String requestId,
    required String exceptionId,
    required int revision,
    required this.action,
    required this.reason,
  }) : requestId = exceptionUuid(requestId),
       exceptionId = exceptionUuid(exceptionId),
       revision = _revision(revision);
  final String requestId, exceptionId;
  final int revision;
  final AdminExceptionAction action;
  final AdminExceptionReviewReason reason;
  Map<String, dynamic> get parameters => {
    'p_request_id': requestId,
    'p_exception_id': exceptionId,
    'p_expected_revision': revision,
    'p_action': action.wire,
    'p_reason_code': reason.wire,
  };
  factory AdminExceptionIntent.fromParameters(Map<String, dynamic> value) {
    final data = exceptionObject(value, {
      'p_request_id',
      'p_exception_id',
      'p_expected_revision',
      'p_action',
      'p_reason_code',
    });
    return AdminExceptionIntent(
      requestId: exceptionUuid(data['p_request_id']),
      exceptionId: exceptionUuid(data['p_exception_id']),
      revision: _revision(data['p_expected_revision']),
      action: AdminExceptionAction.parse(data['p_action']),
      reason: AdminExceptionReviewReason.parse(data['p_reason_code']),
    );
  }
}

class AdminExceptionReceipt {
  const AdminExceptionReceipt._(
    this.requestId,
    this.exceptionId,
    this.revision,
    this.action,
    this.recordedAt,
  );
  final String requestId, exceptionId;
  final int revision;
  final AdminExceptionAction action;
  final DateTime recordedAt;
  bool matches(AdminExceptionIntent intent) =>
      requestId == intent.requestId &&
      exceptionId == intent.exceptionId &&
      revision == intent.revision &&
      action == intent.action;
  factory AdminExceptionReceipt.parse(
    Object? value, {
    AdminExceptionIntent? intent,
  }) {
    final data = exceptionObject(value, {
      'contract_version',
      'request_id',
      'exception_id',
      'revision',
      'action',
      'recorded_at',
      'source_resolved',
      'financial_action',
      'send_action',
      'escalation_delivery_verified',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        data['source_resolved'] != false ||
        data['financial_action'] != false ||
        data['send_action'] != false ||
        data['escalation_delivery_verified'] != false) {
      exceptionInvalid();
    }
    final result = AdminExceptionReceipt._(
      exceptionUuid(data['request_id']),
      exceptionUuid(data['exception_id']),
      _revision(data['revision']),
      AdminExceptionAction.parse(data['action']),
      exceptionInstant(data['recorded_at']),
    );
    if (intent != null && !result.matches(intent)) exceptionInvalid();
    return result;
  }
}

class AdminExceptionLookup {
  const AdminExceptionLookup._(
    this.checkedAt,
    this.validUntil,
    this.status,
    this.receipt,
  );
  final DateTime checkedAt, validUntil;
  final String status;
  final AdminExceptionReceipt? receipt;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminExceptionLookup.parse(
    Map<String, dynamic> raw, {
    required String requestId,
  }) {
    final data = exceptionObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'request_id',
      'status',
      'receipt',
    });
    final status = data['status'];
    if (data['contract_version'] is! int ||
        data['contract_version'] != 2 ||
        data['scope'] != 'platform_global' ||
        exceptionUuid(data['request_id']) != exceptionUuid(requestId) ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(status)) {
      exceptionInvalid();
    }
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60) ||
        (status == 'recorded') != (data['receipt'] != null)) {
      exceptionInvalid();
    }
    final receipt = data['receipt'] == null
        ? null
        : AdminExceptionReceipt.parse(data['receipt']);
    if (receipt != null &&
        (receipt.requestId != requestId ||
            receipt.recordedAt.isAfter(checked))) {
      exceptionInvalid();
    }
    return AdminExceptionLookup._(checked, until, status as String, receipt);
  }
}

bool adminExceptionActionReceiptMatches(
  Map<String, dynamic> request,
  Map<String, dynamic> response,
) {
  try {
    AdminExceptionReceipt.parse(
      response,
      intent: AdminExceptionIntent.fromParameters(request),
    );
    return true;
  } on FormatException {
    return false;
  }
}
