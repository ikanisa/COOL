import '../../core/data/exact_json_values.dart';
import 'admin_transaction_lifecycle.dart';

/// Redacted service evidence. These timestamps describe separate observations;
/// neither a posted row nor an operator readback attests carrier delivery.
class AdminInvestigationSnapshot {
  const AdminInvestigationSnapshot._({
    required this.kind,
    required this.scope,
    required this.targetId,
    required this.checkedAt,
    required this.validUntil,
    required this.paymentState,
    required this.receiptState,
    required this.payment,
    required this.receipt,
  });
  final String kind, scope, targetId, paymentState, receiptState;
  final DateTime checkedAt, validUntil;
  final AdminInvestigationPayment? payment;
  final AdminInvestigationReceipt? receipt;

  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);

  factory AdminInvestigationSnapshot.parse(Map<String, dynamic> raw) {
    final data = _object(raw, {
      'contract_version',
      'scope',
      'kind',
      'target_id',
      'history_limit',
      'checked_at',
      'sample_valid_until',
      'payment_state',
      'payment',
      'receipt_state',
      'receipt',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        !{'rwanda_momo', 'unclassified'}.contains(data['scope']) ||
        data['history_limit'] is! int ||
        data['history_limit'] != 50 ||
        !{'transaction', 'receipt'}.contains(data['kind'])) {
      _invalid();
    }
    final kind = data['kind'] as String;
    final target = _uuid(data['target_id']);
    final checked = _date(data['checked_at']);
    final valid = _date(data['sample_valid_until']);
    if (valid.difference(checked) != const Duration(seconds: 60)) {
      _invalid();
    }
    final paymentState = _state(data['payment_state'], {
      'available',
      'missing',
      'denied',
      'unsupported',
    });
    final receiptState = _state(data['receipt_state'], {
      'available',
      'missing',
      'denied',
      'unsupported',
    });
    final payment = paymentState == 'available'
        ? AdminInvestigationPayment._parse(data['payment'])
        : null;
    final receipt = receiptState == 'available'
        ? AdminInvestigationReceipt._parse(data['receipt'])
        : null;
    if ((paymentState != 'available' && data['payment'] != null) ||
        (data['scope'] == 'unclassified' &&
            (paymentState == 'available' || receiptState == 'available')) ||
        (data['scope'] == 'rwanda_momo' &&
            (paymentState == 'unsupported' || receiptState == 'unsupported')) ||
        (receiptState != 'available' && data['receipt'] != null) ||
        (kind == 'transaction' && paymentState == 'denied') ||
        (kind == 'receipt' && receiptState == 'denied') ||
        (kind == 'transaction' &&
            payment != null &&
            payment.rawSmsId != target) ||
        (kind == 'receipt' && receipt != null && receipt.id != target) ||
        (payment != null &&
            receipt != null &&
            (payment.paymentId != receipt.paymentId ||
                payment.collectionId != receipt.collectionId ||
                payment.memberId != receipt.memberId))) {
      _invalid();
    }
    if (payment != null && receipt != null) {
      final postings = payment.journals.where(
        (journal) => journal.entryType == 'receipt',
      );
      final snapshot = postings.isEmpty ? null : postings.single.snapshot;
      // A reconstructed receipt claims one immutable posting. Validate that
      // provenance against the independently returned journal, never against
      // the mutable current balances.
      if (receipt.snapshotCapturedAt != null &&
          (snapshot == null ||
              snapshot.id != receipt.snapshotId ||
              snapshot.capturedAt != receipt.snapshotCapturedAt ||
              snapshot.memberRwf != receipt.memberRwf ||
              snapshot.groupRwf != receipt.groupRwf ||
              postings.single.amountRwf != receipt.amountRwf)) {
        _invalid();
      }
    }
    return AdminInvestigationSnapshot._(
      kind: kind,
      scope: data['scope'] as String,
      targetId: target,
      checkedAt: checked,
      validUntil: valid,
      paymentState: paymentState,
      receiptState: receiptState,
      payment: payment,
      receipt: receipt,
    );
  }
}

class AdminInvestigationPayment {
  const AdminInvestigationPayment._({
    required this.paymentId,
    required this.rawSmsId,
    required this.eventId,
    required this.collectionId,
    required this.memberId,
    required this.lifecycle,
    required this.times,
    required this.journals,
    required this.currentBalances,
  });
  final String? paymentId, rawSmsId, eventId, collectionId, memberId;
  final AdminTransactionLifecycle? lifecycle;
  final Map<String, DateTime?> times;
  final List<AdminInvestigationJournal> journals;
  final AdminInvestigationCurrentBalances currentBalances;

  factory AdminInvestigationPayment._parse(Object? raw) {
    final data = _object(raw, {
      'payment_id',
      'raw_sms_id',
      'event_id',
      'collection_id',
      'member_record_id',
      'lifecycle',
      'times',
      'journals',
      'current_balances',
    });
    final sms = _nullableUuid(data['raw_sms_id']);
    final lifecycle = AdminTransactionLifecycle.parse(data['lifecycle']);
    if ((sms == null) != (lifecycle == null)) {
      _invalid();
    }
    final times = _object(data['times'], {
      'received_at_device',
      'ingested_at',
      'parsed_recorded_at',
      'allocation_recorded_at',
      'provider_confirmed_at',
      'confirmation_recorded_at',
      'rejection_occurred_at',
      'rejection_recorded_at',
      'payment_posted_at',
    }).map((key, value) => MapEntry(key, _nullableDate(value)));
    final rows = _list(
      data['journals'],
      2,
    ).map(AdminInvestigationJournal._parse).toList();
    if (rows.map((row) => row.entryType).toSet().length != rows.length) {
      _invalid();
    }
    return AdminInvestigationPayment._(
      paymentId: _nullableUuid(data['payment_id']),
      rawSmsId: sms,
      eventId: _nullableUuid(data['event_id']),
      collectionId: _nullableUuid(data['collection_id']),
      memberId: _nullableUuid(data['member_record_id']),
      lifecycle: lifecycle,
      times: Map.unmodifiable(times),
      journals: List.unmodifiable(rows),
      currentBalances: AdminInvestigationCurrentBalances._parse(
        data['current_balances'],
      ),
    );
  }
}

class AdminInvestigationCurrentBalances {
  const AdminInvestigationCurrentBalances._(
    this.memberRwf,
    this.memberUpdatedAt,
    this.groupRwf,
    this.groupUpdatedAt,
  );
  final String? memberRwf, groupRwf;
  final DateTime? memberUpdatedAt, groupUpdatedAt;
  factory AdminInvestigationCurrentBalances._parse(Object? raw) {
    final data = _object(raw, {
      'member_rwf',
      'member_updated_at',
      'group_rwf',
      'group_updated_at',
    });
    final member = _nullableMoney(data['member_rwf']);
    final group = _nullableMoney(data['group_rwf']);
    final memberTime = _nullableDate(data['member_updated_at']);
    final groupTime = _nullableDate(data['group_updated_at']);
    if ((member == null) != (memberTime == null) ||
        (group == null) != (groupTime == null)) {
      _invalid();
    }
    return AdminInvestigationCurrentBalances._(
      member,
      memberTime,
      group,
      groupTime,
    );
  }
}

class AdminInvestigationJournal {
  const AdminInvestigationJournal._(
    this.id,
    this.entryType,
    this.amountRwf,
    this.postedAt,
    this.snapshot,
  );
  final String id, entryType, amountRwf;
  final DateTime postedAt;
  final AdminInvestigationBalanceSnapshot? snapshot;
  factory AdminInvestigationJournal._parse(Object? raw) {
    final data = _object(raw, {
      'id',
      'entry_type',
      'amount_rwf',
      'posted_at',
      'snapshot',
    });
    final type = _state(data['entry_type'], {'receipt', 'reversal'});
    final amount = _money(data['amount_rwf'], positive: true);
    final snapshot = data['snapshot'] == null
        ? null
        : AdminInvestigationBalanceSnapshot._parse(data['snapshot']);
    if (snapshot != null &&
        snapshot.deltaRwf != '${type == 'reversal' ? '-' : ''}$amount') {
      _invalid();
    }
    return AdminInvestigationJournal._(
      _uuid(data['id']),
      type,
      amount,
      _date(data['posted_at']),
      snapshot,
    );
  }
}

class AdminInvestigationBalanceSnapshot {
  const AdminInvestigationBalanceSnapshot._(
    this.id,
    this.capturedAt,
    this.deltaRwf,
    this.memberRwf,
    this.groupRwf,
  );
  final String id, deltaRwf, groupRwf;
  final String? memberRwf;
  final DateTime capturedAt;
  factory AdminInvestigationBalanceSnapshot._parse(Object? raw) {
    final data = _object(raw, {
      'id',
      'captured_at',
      'delta_rwf',
      'member_balance_rwf',
      'group_balance_rwf',
    });
    final delta = data['delta_rwf'];
    if (delta is! String || !RegExp(r'^-?[1-9][0-9]{0,18}$').hasMatch(delta)) {
      _invalid();
    }
    _money(delta.startsWith('-') ? delta.substring(1) : delta, positive: true);
    return AdminInvestigationBalanceSnapshot._(
      _uuid(data['id']),
      _date(data['captured_at']),
      delta,
      _nullableMoney(data['member_balance_rwf']),
      _money(data['group_balance_rwf']),
    );
  }
}

class AdminInvestigationReceipt {
  const AdminInvestigationReceipt._({
    required this.id,
    required this.paymentId,
    required this.snapshotId,
    required this.collectionId,
    required this.memberId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.observedSentAt,
    required this.maskedDestination,
    required this.amountRwf,
    required this.memberRwf,
    required this.groupRwf,
    required this.snapshotCapturedAt,
    required this.maskedSnapshotPreview,
    required this.approvals,
    required this.approvalTotal,
    required this.attempts,
    required this.attemptTotal,
  });
  final String id,
      paymentId,
      snapshotId,
      collectionId,
      memberId,
      state,
      maskedDestination;
  final String amountRwf, memberRwf, groupRwf;
  final DateTime createdAt, updatedAt;
  final DateTime? observedSentAt, snapshotCapturedAt;
  final String? maskedSnapshotPreview;
  final List<AdminInvestigationApproval> approvals;
  final int approvalTotal;
  final List<AdminInvestigationAttempt> attempts;
  final int attemptTotal;
  bool get partialHistory =>
      approvalTotal > approvals.length || attemptTotal > attempts.length;

  factory AdminInvestigationReceipt._parse(Object? raw) {
    final data = _object(raw, {
      'id',
      'payment_id',
      'snapshot_id',
      'collection_id',
      'member_record_id',
      'state',
      'template_key',
      'template_version',
      'created_at',
      'updated_at',
      'observed_sent_at',
      'masked_destination',
      'amount_rwf',
      'member_balance_rwf',
      'group_balance_rwf',
      'snapshot_captured_at',
      'preview_source',
      'masked_snapshot_preview',
      'approvals',
      'approval_total',
      'attempts',
      'attempt_total',
    });
    if (data['template_key'] != 'buri_munsi.payment_received' ||
        data['template_version'] is! int ||
        data['template_version'] != 1) {
      _invalid();
    }
    final destination = data['masked_destination'];
    if (destination is! String ||
        !RegExp(r'^\+250•••[0-9]{3}$').hasMatch(destination)) {
      _invalid();
    }
    final captured = _nullableDate(data['snapshot_captured_at']);
    final preview = data['masked_snapshot_preview'];
    if (data['preview_source'] == 'immutable_posting_snapshot') {
      if (captured == null ||
          preview is! String ||
          preview.isEmpty ||
          preview.length > 480 ||
          RegExp(r'[\u0000-\u001F\u007F]|\+2507[0-9]{8}').hasMatch(preview)) {
        _invalid();
      }
    } else if (data['preview_source'] != 'snapshot_unavailable' ||
        captured != null ||
        preview != null) {
      _invalid();
    }
    final approvals = _list(
      data['approvals'],
      50,
    ).map(AdminInvestigationApproval._parse).toList();
    final attempts = _list(
      data['attempts'],
      50,
    ).map(AdminInvestigationAttempt._parse).toList();
    final approvalTotal = _count(data['approval_total']);
    final attemptTotal = _count(data['attempt_total']);
    if (approvals.length != (approvalTotal > 50 ? 50 : approvalTotal) ||
        attempts.length != (attemptTotal > 50 ? 50 : attemptTotal) ||
        approvals.map((row) => row.id).toSet().length != approvals.length ||
        attempts.map((row) => row.id).toSet().length != attempts.length) {
      _invalid();
    }
    for (var i = 1; i < approvals.length; i++) {
      final previous = approvals[i - 1], current = approvals[i];
      if (previous.approvedAt.isBefore(current.approvedAt) ||
          (previous.approvedAt == current.approvedAt &&
              previous.id.compareTo(current.id) <= 0)) {
        _invalid();
      }
    }
    for (var i = 1; i < attempts.length; i++) {
      if (attempts[i - 1].number <= attempts[i].number) {
        _invalid();
      }
    }
    return AdminInvestigationReceipt._(
      id: _uuid(data['id']),
      paymentId: _uuid(data['payment_id']),
      snapshotId: _uuid(data['snapshot_id']),
      collectionId: _uuid(data['collection_id']),
      memberId: _uuid(data['member_record_id']),
      state: _state(data['state'], {
        'queued',
        'awaiting_confirmation',
        'send_started',
        'observed_sent',
        'failed_no_send',
        'uncertain',
        'suppressed',
      }),
      createdAt: _date(data['created_at']),
      updatedAt: _date(data['updated_at']),
      observedSentAt: _nullableDate(data['observed_sent_at']),
      maskedDestination: destination,
      amountRwf: _money(data['amount_rwf'], positive: true),
      memberRwf: _money(data['member_balance_rwf']),
      groupRwf: _money(data['group_balance_rwf']),
      snapshotCapturedAt: captured,
      maskedSnapshotPreview: preview as String?,
      approvals: List.unmodifiable(approvals),
      approvalTotal: approvalTotal,
      attempts: List.unmodifiable(attempts),
      attemptTotal: attemptTotal,
    );
  }
}

class AdminInvestigationApproval {
  const AdminInvestigationApproval._(
    this.id,
    this.approvedAt,
    this.expiresAt,
    this.consumedAt,
  );
  final String id;
  final DateTime approvedAt, expiresAt;
  final DateTime? consumedAt;
  factory AdminInvestigationApproval._parse(Object? raw) {
    final data = _object(raw, {
      'id',
      'approved_at',
      'expires_at',
      'consumed_at',
    });
    final approved = _date(data['approved_at']),
        expires = _date(data['expires_at']);
    final consumed = _nullableDate(data['consumed_at']);
    if (!expires.isAfter(approved) ||
        (consumed != null && consumed.isBefore(approved))) {
      _invalid();
    }
    return AdminInvestigationApproval._(
      _uuid(data['id']),
      approved,
      expires,
      consumed,
    );
  }
}

class AdminInvestigationAttempt {
  const AdminInvestigationAttempt._(
    this.id,
    this.number,
    this.state,
    this.startedAt,
    this.outcomeAt,
  );
  final String id, state;
  final int number;
  final DateTime startedAt;
  final DateTime? outcomeAt;
  factory AdminInvestigationAttempt._parse(Object? raw) {
    final data = _object(raw, {
      'id',
      'attempt_number',
      'state',
      'send_started_at',
      'outcome_at',
    });
    final number = _count(data['attempt_number']);
    final state = _state(data['state'], {
      'send_started',
      'observed_sent',
      'failed_no_send',
      'uncertain',
    });
    final started = _date(data['send_started_at']),
        outcome = _nullableDate(data['outcome_at']);
    if (number == 0 ||
        (state == 'send_started') != (outcome == null) ||
        (outcome != null && outcome.isBefore(started))) {
      _invalid();
    }
    return AdminInvestigationAttempt._(
      _uuid(data['id']),
      number,
      state,
      started,
      outcome,
    );
  }
}

Never _invalid() => throw const FormatException(
  'Investigation evidence could not be validated.',
);
Map<String, dynamic> _object(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((key) => key is! String || !keys.contains(key))) {
    _invalid();
  }
  return Map<String, dynamic>.from(raw);
}

String _uuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    _invalid();
  }
  return raw;
}

String? _nullableUuid(Object? raw) => raw == null ? null : _uuid(raw);
String _state(Object? raw, Set<String> values) {
  if (raw is! String || !values.contains(raw)) {
    _invalid();
  }
  return raw;
}

DateTime _date(Object? raw) {
  if (raw is! String) {
    _invalid();
  }
  return exactJsonTimestamp(raw, field: 'investigation timestamp');
}

DateTime? _nullableDate(Object? raw) => raw == null ? null : _date(raw);
int _count(Object? raw) {
  if (raw is! int) {
    _invalid();
  }
  return exactJsonInteger(raw, field: 'investigation count', minimum: 0);
}

String _money(Object? raw, {bool positive = false}) {
  if (raw is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(raw) ||
      BigInt.parse(raw) > BigInt.parse('9223372036854775807') ||
      (positive && raw == '0')) {
    _invalid();
  }
  return raw;
}

String? _nullableMoney(Object? raw) => raw == null ? null : _money(raw);
List<Object?> _list(Object? raw, int limit) {
  if (raw is! List || raw.length > limit) {
    _invalid();
  }
  return List<Object?>.from(raw);
}
