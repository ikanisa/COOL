import 'dart:convert';
import 'package:crypto/crypto.dart';

Never compensationInvalid() =>
    throw const FormatException('Invalid compensation evidence');
Map<String, dynamic> compensationObject(Object? value, Set<String> keys) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    compensationInvalid();
  }
  final row = Map<String, dynamic>.from(value);
  if (row.length != keys.length || !keys.every(row.containsKey)) {
    compensationInvalid();
  }
  return row;
}

String compensationUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    compensationInvalid();
  }
  return value;
}

String compensationHash(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    compensationInvalid();
  }
  return value;
}

DateTime compensationTime(Object? value) {
  if (value is! String || !value.endsWith('Z')) compensationInvalid();
  final result = DateTime.tryParse(value);
  if (result == null || !result.isUtc) compensationInvalid();
  return result;
}

String compensationMoney(Object? value, {bool negative = false}) {
  if (value is! String ||
      !RegExp(
        negative ? r'^-[1-9][0-9]{0,18}$' : r'^(0|[1-9][0-9]{0,18})$',
      ).hasMatch(value)) {
    compensationInvalid();
  }
  final amount = BigInt.parse(value);
  if (amount.abs() > BigInt.parse('9223372036854775807')) compensationInvalid();
  return value;
}

String compensationFingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
String compensationReason(String value) {
  final clean = value.trim();
  if (clean.runes.length < 8 ||
      clean.runes.length > 500 ||
      clean.contains('\u0000')) {
    compensationInvalid();
  }
  return clean;
}

void _base(Map<String, dynamic> row, {bool financial = false}) {
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != 'rw_admin_full_payment_compensation' ||
      row['financial_action'] != financial ||
      row['send_action'] != false ||
      row['provider_reversal'] != false ||
      row['sender_armed_recall'] != false) {
    compensationInvalid();
  }
}

bool compensationFresh(DateTime checked, DateTime until, DateTime now) =>
    !now.toUtc().isBefore(checked) && now.toUtc().isBefore(until);

class AdminFullPaymentCompensationSource {
  AdminFullPaymentCompensationSource._(this.row);
  factory AdminFullPaymentCompensationSource.parse(Object? value) {
    final row = compensationObject(value, {
      'payment_id',
      'collection_id',
      'member_record_id',
      'original_journal_entry_id',
      'original_snapshot_id',
      'provider_network',
      'reference',
      'currency',
      'amount_rwf',
      'original_recorded_at',
      'original_member_balance_recorded_rwf',
      'original_group_balance_recorded_rwf',
      'member_balance_current_rwf',
      'group_balance_current_rwf',
      'member_balance_after_compensation_rwf',
      'group_balance_after_compensation_rwf',
      'source_sha256',
    });
    for (final key in [
      'payment_id',
      'collection_id',
      'original_journal_entry_id',
      'original_snapshot_id',
    ]) {
      compensationUuid(row[key]);
    }
    if (row['member_record_id'] != null) {
      compensationUuid(row['member_record_id']);
    }
    if (!['mtn_momo', 'airtel_money'].contains(row['provider_network']) ||
        row['currency'] != 'RWF' ||
        row['reference'] is! String ||
        (row['reference'] as String).trim() != row['reference'] ||
        (row['reference'] as String).length < 3 ||
        (row['reference'] as String).length > 128) {
      compensationInvalid();
    }
    final amount = BigInt.parse(compensationMoney(row['amount_rwf']));
    if (amount <= BigInt.zero) compensationInvalid();
    compensationTime(row['original_recorded_at']);
    compensationHash(row['source_sha256']);
    for (final key in [
      'original_group_balance_recorded_rwf',
      'group_balance_current_rwf',
      'group_balance_after_compensation_rwf',
    ]) {
      compensationMoney(row[key]);
    }
    for (final key in [
      'original_member_balance_recorded_rwf',
      'member_balance_current_rwf',
      'member_balance_after_compensation_rwf',
    ]) {
      if (row['member_record_id'] == null) {
        if (row[key] != null) compensationInvalid();
      } else {
        compensationMoney(row[key]);
      }
    }
    if (BigInt.parse(row['original_group_balance_recorded_rwf'] as String) <
            amount ||
        BigInt.parse(row['group_balance_current_rwf'] as String) - amount !=
            BigInt.parse(
              row['group_balance_after_compensation_rwf'] as String,
            )) {
      compensationInvalid();
    }
    if (row['member_record_id'] != null &&
        (BigInt.parse(row['original_member_balance_recorded_rwf'] as String) <
                amount ||
            BigInt.parse(row['member_balance_current_rwf'] as String) -
                    amount !=
                BigInt.parse(
                  row['member_balance_after_compensation_rwf'] as String,
                ))) {
      compensationInvalid();
    }
    return AdminFullPaymentCompensationSource._(Map.unmodifiable(row));
  }
  final Map<String, dynamic> row;
  String get paymentId => row['payment_id'] as String;
  String get collectionId => row['collection_id'] as String;
  String? get memberRecordId => row['member_record_id'] as String?;
  String get originalJournalEntryId =>
      row['original_journal_entry_id'] as String;
  String get originalSnapshotId => row['original_snapshot_id'] as String;
  String get amountRwf => row['amount_rwf'] as String;
  String get sourceSha256 => row['source_sha256'] as String;
  bool matches(
    String payment,
    String journal,
    String snapshot,
    String collection,
    String? member,
  ) =>
      paymentId == payment &&
      originalJournalEntryId == journal &&
      originalSnapshotId == snapshot &&
      collectionId == collection &&
      memberRecordId == member;
}

class AdminFullPaymentCompensationInspection {
  AdminFullPaymentCompensationInspection._(
    this.row,
    this.source,
    this.checkedAt,
    this.sampleValidUntil,
  );
  factory AdminFullPaymentCompensationInspection.parse(Object? value) {
    final row = compensationObject(value, {
      'contract_version',
      'scope',
      'payment_id',
      'checked_at',
      'sample_valid_until',
      'revision',
      'reason_code',
      'can_record',
      'candidate_sha256',
      'source',
      'financial_action',
      'send_action',
      'provider_reversal',
      'sender_armed_recall',
    });
    _base(row);
    compensationUuid(row['payment_id']);
    final checked = compensationTime(row['checked_at']),
        until = compensationTime(row['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60) ||
        row['revision'] is! int ||
        ![1, 2].contains(row['revision']) ||
        ![
          'eligible',
          'payment_unavailable',
          'payment_already_reversed',
          'financial_source_invalid',
          'insufficient_recorded_balance',
        ].contains(row['reason_code']) ||
        row['can_record'] != (row['reason_code'] == 'eligible')) {
      compensationInvalid();
    }
    AdminFullPaymentCompensationSource? source;
    if (row['can_record'] == true) {
      if (row['revision'] != 1) compensationInvalid();
      compensationHash(row['candidate_sha256']);
      source = AdminFullPaymentCompensationSource.parse(row['source']);
      if (source.paymentId != row['payment_id'] ||
          compensationTime(
            source.row['original_recorded_at'],
          ).isAfter(checked)) {
        compensationInvalid();
      }
    } else if (row['source'] != null || row['candidate_sha256'] != null) {
      compensationInvalid();
    }
    row['source'] = source?.row;
    return AdminFullPaymentCompensationInspection._(
      Map.unmodifiable(row),
      source,
      checked,
      until,
    );
  }
  final Map<String, dynamic> row;
  final AdminFullPaymentCompensationSource? source;
  final DateTime checkedAt, sampleValidUntil;
  String get paymentId => row['payment_id'] as String;
  bool get canRecord => row['can_record'] as bool;
  bool fresh(DateTime now) =>
      compensationFresh(checkedAt, sampleValidUntil, now);
}

class AdminFullPaymentCompensationIntent {
  AdminFullPaymentCompensationIntent._(this.row, this.inspection);
  factory AdminFullPaymentCompensationIntent.create({
    required String requestId,
    required String actorId,
    required String sessionId,
    required AdminFullPaymentCompensationInspection inspection,
    required String reason,
  }) => AdminFullPaymentCompensationIntent.parse({
    'version': 1,
    'request_id': requestId,
    'actor_id': actorId,
    'session_id': sessionId,
    'inspection': inspection.row,
    'reason': compensationReason(reason),
  });
  factory AdminFullPaymentCompensationIntent.parse(Object? value) {
    final row = compensationObject(value, {
      'version',
      'request_id',
      'actor_id',
      'session_id',
      'inspection',
      'reason',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        row['reason'] is! String ||
        compensationReason(row['reason'] as String) != row['reason']) {
      compensationInvalid();
    }
    for (final key in ['request_id', 'actor_id', 'session_id']) {
      compensationUuid(row[key]);
    }
    final inspection = AdminFullPaymentCompensationInspection.parse(
      row['inspection'],
    );
    if (!inspection.canRecord) compensationInvalid();
    row['inspection'] = inspection.row;
    return AdminFullPaymentCompensationIntent._(
      Map.unmodifiable(row),
      inspection,
    );
  }
  final Map<String, dynamic> row;
  final AdminFullPaymentCompensationInspection inspection;
  String get requestId => row['request_id'] as String;
  String get actorId => row['actor_id'] as String;
  String get sessionId => row['session_id'] as String;
  String get reason => row['reason'] as String;
  String get fingerprint => compensationFingerprint(row);
  Map<String, dynamic> get parameters => {
    'p_request_id': requestId,
    'p_payment_id': inspection.paymentId,
    'p_expected_revision': inspection.row['revision'],
    'p_candidate_sha256': inspection.row['candidate_sha256'],
    'p_sample_valid_until': inspection.row['sample_valid_until'],
    'p_reason': reason,
  };
}

class AdminFullPaymentCompensationResult {
  AdminFullPaymentCompensationResult._(this.row);
  factory AdminFullPaymentCompensationResult.parse(
    Object? value,
    AdminFullPaymentCompensationIntent original,
  ) {
    final row = compensationObject(value, {
      'contract_version',
      'scope',
      'request_id',
      'action',
      'payment_id',
      'collection_id',
      'member_record_id',
      'original_journal_entry_id',
      'original_snapshot_id',
      'compensation_journal_entry_id',
      'compensation_snapshot_id',
      'expected_revision',
      'revision',
      'candidate_sha256',
      'source_sha256',
      'sample_valid_until',
      'reason_sha256',
      'reason_characters',
      'amount_rwf',
      'delta_rwf',
      'currency',
      'member_balance_after_compensation_rwf',
      'group_balance_after_compensation_rwf',
      'status',
      'recorded_at',
      'audit_id',
      'financial_action',
      'send_action',
      'provider_reversal',
      'sender_armed_recall',
    });
    _base(row, financial: true);
    final source = original.inspection.source!;
    for (final key in [
      'request_id',
      'payment_id',
      'collection_id',
      'original_journal_entry_id',
      'original_snapshot_id',
      'compensation_journal_entry_id',
      'compensation_snapshot_id',
      'audit_id',
    ]) {
      compensationUuid(row[key]);
    }
    if (row['member_record_id'] != null) {
      compensationUuid(row['member_record_id']);
    }
    if (row['action'] != 'full_ledger_compensation' ||
        row['status'] != 'recorded' ||
        row['request_id'] != original.requestId ||
        row['expected_revision'] is! int ||
        row['expected_revision'] != 1 ||
        row['revision'] is! int ||
        row['revision'] != 2 ||
        row['candidate_sha256'] !=
            original.inspection.row['candidate_sha256'] ||
        row['source_sha256'] != source.sourceSha256 ||
        row['sample_valid_until'] !=
            original.inspection.row['sample_valid_until'] ||
        row['reason_sha256'] !=
            sha256.convert(utf8.encode(original.reason)).toString() ||
        row['reason_characters'] is! int ||
        row['reason_characters'] != original.reason.runes.length ||
        row['currency'] != 'RWF') {
      compensationInvalid();
    }
    for (final key in [
      'payment_id',
      'collection_id',
      'member_record_id',
      'original_journal_entry_id',
      'original_snapshot_id',
      'amount_rwf',
      'member_balance_after_compensation_rwf',
      'group_balance_after_compensation_rwf',
    ]) {
      if (row[key] != source.row[key]) compensationInvalid();
    }
    compensationMoney(row['delta_rwf'], negative: true);
    if (row['delta_rwf'] != '-${source.amountRwf}' ||
        row['compensation_journal_entry_id'] ==
            row['original_journal_entry_id'] ||
        row['compensation_snapshot_id'] == row['original_snapshot_id'] ||
        compensationTime(
          row['recorded_at'],
        ).isBefore(original.inspection.checkedAt)) {
      compensationInvalid();
    }
    return AdminFullPaymentCompensationResult._(Map.unmodifiable(row));
  }
  final Map<String, dynamic> row;
}

class AdminFullPaymentCompensationLookup {
  AdminFullPaymentCompensationLookup._(
    this.status,
    this.result,
    this.checkedAt,
    this.sampleValidUntil,
  );
  factory AdminFullPaymentCompensationLookup.parse(
    Object? value,
    AdminFullPaymentCompensationIntent original,
  ) {
    final row = compensationObject(value, {
      'contract_version',
      'scope',
      'request_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'result',
      'financial_action',
      'send_action',
      'provider_reversal',
      'sender_armed_recall',
    });
    _base(row);
    if (row['request_id'] != original.requestId ||
        !['recorded', 'in_progress', 'not_recorded'].contains(row['status'])) {
      compensationInvalid();
    }
    final checked = compensationTime(row['checked_at']),
        until = compensationTime(row['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      compensationInvalid();
    }
    final result = row['status'] == 'recorded'
        ? AdminFullPaymentCompensationResult.parse(row['result'], original)
        : null;
    if (result == null && row['result'] != null) compensationInvalid();
    if (result != null &&
        compensationTime(result.row['recorded_at']).isAfter(checked)) {
      compensationInvalid();
    }
    return AdminFullPaymentCompensationLookup._(
      row['status'] as String,
      result,
      checked,
      until,
    );
  }
  final String status;
  final AdminFullPaymentCompensationResult? result;
  final DateTime checkedAt, sampleValidUntil;
  bool fresh(DateTime now) =>
      compensationFresh(checkedAt, sampleValidUntil, now);
}
