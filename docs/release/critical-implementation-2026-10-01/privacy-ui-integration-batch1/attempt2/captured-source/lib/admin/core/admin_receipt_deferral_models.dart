import 'admin_exception_models.dart';

/// The server reports business handling independently of transport outcomes.
/// A cleared blocker or a superseded source is never a handling acknowledgement.
class AdminReceiptDeferralEvidence {
  const AdminReceiptDeferralEvidence._({
    required this.exceptionId,
    required this.source,
    required this.sourceId,
    required this.sourceVersion,
    required this.eventKind,
    required this.reasonCode,
    required this.revision,
    required this.active,
    required this.disposition,
    required this.originalCode,
    required this.currentCode,
    required this.businessHandled,
    required this.receiptId,
    required this.checkedAt,
    required this.validUntil,
  });

  final String exceptionId, sourceId, reasonCode, disposition;
  final AdminExceptionSource source;
  final int? sourceVersion;
  final int revision;
  final String? eventKind, originalCode, currentCode, receiptId;
  final bool active, businessHandled;
  final DateTime checkedAt, validUntil;

  static const eventKinds = {
    'payment_posted',
    'payment_reversed',
    'allocation_changed',
    'receipt_created',
    'receipt_failed_no_send',
    'receipt_uncertain',
    'receipt_suppressed',
  };
  static const handledCodes = {
    'RECEIPT_ENQUEUED',
    'RECEIPT_EXISTS',
    'PAYMENT_REVERSED',
    'SOURCE_SUPERSEDED',
  };
  static const _codeLabels = {
    'RECEIPT_ENQUEUED': 'Receipt saved in the queue',
    'RECEIPT_EXISTS': 'Existing receipt verified',
    'PAYMENT_REVERSED': 'Payment reversal handled',
    'SOURCE_SUPERSEDED': 'A later source version exists',
    'DRY_RUN_ELIGIBLE': 'Currently eligible for receipt creation',
  };
  static String? _code(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !adminReceiptDeferralLabels.containsKey(value) &&
            !_codeLabels.containsKey(value)) {
      exceptionInvalid();
    }
    return value;
  }

  String get reasonLabel => adminExceptionReasonLabel(source, reasonCode)!;
  String? get originalLabel => originalCode == null
      ? null
      : adminReceiptDeferralLabels[originalCode] ?? _codeLabels[originalCode];
  String? get currentLabel => currentCode == null
      ? null
      : adminReceiptDeferralLabels[currentCode] ?? _codeLabels[currentCode];
  String get dispositionLabel => switch (disposition) {
    'deferred' => 'Receipt work deferred',
    'current_blocker_cleared' => 'Current blocker cleared',
    'source_superseded' => 'Source superseded',
    _ => 'Receipt work durably handled',
  };
  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);

  factory AdminReceiptDeferralEvidence.parse(Object? raw, String exceptionId) {
    final data = exceptionObject(raw, {
      'contract_version',
      'exception_id',
      'source_kind',
      'source_id',
      'source_version',
      'event_kind',
      'reason_code',
      'revision',
      'active',
      'disposition',
      'original_code',
      'current_code',
      'business_handled',
      'receipt_id',
      'checked_at',
      'sample_valid_until',
      'financial_action',
      'send_action',
    });
    final source = AdminExceptionSource.parse(data['source_kind']);
    final version = data['source_version'];
    final revision = data['revision'];
    final reason = data['reason_code'];
    final event = data['event_kind'];
    final disposition = data['disposition'];
    final handled = data['business_handled'];
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        exceptionUuid(data['exception_id']) != exceptionUuid(exceptionId) ||
        !source.isReceiptDeferral ||
        revision is! int ||
        revision < 1 ||
        revision > 1000000000 ||
        reason is! String ||
        adminExceptionReasonLabel(source, reason) == null ||
        data['active'] is! bool ||
        handled is! bool ||
        !{
          'deferred',
          'current_blocker_cleared',
          'source_superseded',
          'durably_handled',
        }.contains(disposition) ||
        data['financial_action'] != false ||
        data['send_action'] != false) {
      exceptionInvalid();
    }
    if (source == AdminExceptionSource.receiptEvent) {
      if (version is! int ||
          version < 1 ||
          version > 1000000000 ||
          !eventKinds.contains(event)) {
        exceptionInvalid();
      }
    } else if (version != null || event != null) {
      exceptionInvalid();
    }
    final original = _code(data['original_code']);
    final current = _code(data['current_code']);
    final receipt = data['receipt_id'] == null
        ? null
        : exceptionUuid(data['receipt_id']);
    // Historical reason/activity belongs to this exception. The current source
    // may have another blocker, so active is not inferred from disposition.
    if (handled != (disposition == 'durably_handled') ||
        current == 'SOURCE_BUSY' && receipt != null ||
        handled && !handledCodes.contains(current) ||
        handled &&
            {'RECEIPT_ENQUEUED', 'RECEIPT_EXISTS'}.contains(current) &&
            receipt == null ||
        disposition == 'source_superseded' &&
            (source != AdminExceptionSource.receiptEvent ||
                current != 'SOURCE_SUPERSEDED' ||
                receipt != null) ||
        disposition == 'deferred' &&
            !adminReceiptDeferralLabels.containsKey(current)) {
      exceptionInvalid();
    }
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      exceptionInvalid();
    }
    return AdminReceiptDeferralEvidence._(
      exceptionId: exceptionId,
      source: source,
      sourceId: exceptionUuid(data['source_id']),
      sourceVersion: version as int?,
      eventKind: event as String?,
      reasonCode: reason,
      revision: revision,
      active: data['active'] as bool,
      disposition: disposition as String,
      originalCode: original,
      currentCode: current,
      businessHandled: handled,
      receiptId: receipt,
      checkedAt: checked,
      validUntil: until,
    );
  }
}
