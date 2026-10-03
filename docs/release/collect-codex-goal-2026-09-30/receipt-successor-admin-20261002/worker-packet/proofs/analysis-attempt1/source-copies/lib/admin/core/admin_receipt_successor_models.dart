import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_receipt_cancel_models.dart';

Never successorInvalid() => throw const FormatException(
  'Receipt successor evidence could not be validated.',
);
Map<String, dynamic> successorObject(Object? raw, Set<String> keys) =>
    cancelObject(raw, keys);
String successorHash(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    successorInvalid();
  }
  return value;
}

void _contract(Map<String, dynamic> row, {bool retained = false}) {
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != 'rw_receipt_successors' ||
      row['financial_action'] != false ||
      row['send_action'] != false ||
      row['carrier_proof'] != false ||
      row['delivery_proven'] != false ||
      retained && row['primary_receipt_retained'] != true) {
    successorInvalid();
  }
}

const _limits = {
  'financial_action',
  'send_action',
  'carrier_proof',
  'delivery_proven',
};
bool successorFresh(DateTime checked, DateTime until, DateTime now) =>
    !now.toUtc().isBefore(checked) && now.toUtc().isBefore(until);

class AdminReceiptClosureInspection {
  AdminReceiptClosureInspection._(this.row, this.checkedAt, this.validUntil);
  final Map<String, dynamic> row;
  final DateTime checkedAt, validUntil;
  String get outboxId => row['outbox_id'] as String;
  String get reason => row['reason_code'] as String;
  bool get canClose => row['can_close'] == true;
  int? get rootRevision => row['root_revision'] as int?;
  int? get lineageRevision => row['lineage_revision'] as int?;
  bool fresh(DateTime now) => successorFresh(checkedAt, validUntil, now);
  factory AdminReceiptClosureInspection.parse(Object? raw, String outbox) {
    final r = successorObject(raw, {
      'contract_version',
      'scope',
      'action',
      'outbox_id',
      'checked_at',
      'sample_valid_until',
      'status',
      'root_revision',
      'lineage_revision',
      'can_close',
      'reason_code',
      'automatic_grant_present',
      ..._limits,
    });
    _contract(r);
    final checked = cancelInstant(r['checked_at']),
        until = cancelInstant(r['sample_valid_until']);
    if (r['outbox_id'] != cancelUuid(outbox) ||
        r['action'] != 'close_unarmed' ||
        until.difference(checked) != const Duration(seconds: 60) ||
        r['can_close'] is! bool ||
        !{
          'unavailable',
          'already_closed',
          'state_not_queued',
          'assisted_transport_present',
          'original_already_armed',
          'source_evidence_invalid',
          'unarmed_eligible',
          'revision_exhausted',
        }.contains(r['reason_code']) ||
        r['can_close'] != (r['reason_code'] == 'unarmed_eligible')) {
      successorInvalid();
    }
    if (r['reason_code'] == 'unavailable') {
      if (r['status'] != 'unavailable' ||
          r['root_revision'] != null ||
          r['lineage_revision'] != null ||
          r['automatic_grant_present'] != null) {
        successorInvalid();
      }
    } else {
      if (r['status'] != 'available' || r['automatic_grant_present'] is! bool)
        successorInvalid();
      r['root_revision'] = cancelRevision(r['root_revision']);
      r['lineage_revision'] = cancelRevision(r['lineage_revision']);
    }
    return AdminReceiptClosureInspection._(Map.unmodifiable(r), checked, until);
  }
}

class AdminReceiptSuccessorPreview {
  AdminReceiptSuccessorPreview._(this.row);
  final Map<String, dynamic> row;
  String get outboxId => row['root_outbox_id'] as String;
  String get sourceId => row['source_snapshot_id'] as String;
  String get body => row['body'] as String;
  String get recipient => row['recipient_masked'] as String;
  String get language => row['language'] as String;
  int get rootRevision => row['root_revision'] as int;
  int get lineageRevision => row['lineage_revision'] as int;
  factory AdminReceiptSuccessorPreview.parse(
    Object? raw,
    String outbox,
    String source,
  ) {
    final r = successorObject(raw, {
      'reason_code',
      'root_outbox_id',
      'closure_id',
      'action',
      'proof_class',
      'transport_proof_sha256',
      'root_revision',
      'lineage_revision',
      'source_snapshot_id',
      'journal_entry_id',
      'source_sha256',
      'payment_id',
      'collection_id',
      'member_record_id',
      'amount_rwf',
      'member_balance_recorded_rwf',
      'snapshot_recorded_at',
      'reference',
      'destination_sha256',
      'destination_revision',
      'policy_revision',
      'consent_revision',
      'language',
      'content_policy_version',
      'body',
      'body_sha256',
      'segment_count',
      'recipient_masked',
    });
    if (r['root_outbox_id'] != cancelUuid(outbox) ||
        r['source_snapshot_id'] != cancelUuid(source) ||
        r['reason_code'] != 'retry_eligible' ||
        r['action'] != 'retry_uninvoked' ||
        r['proof_class'] != 'never_armed_closed' ||
        r['content_policy_version'] is! int ||
        r['content_policy_version'] != 2 ||
        !{'rw', 'en', 'fr'}.contains(r['language']) ||
        r['body'] is! String ||
        utf8.encode(r['body'] as String).length > 1000 ||
        (r['body'] as String).isEmpty ||
        r['recipient_masked'] is! String ||
        !RegExp(
          r'^\+250\*\*\*\d{3}$',
        ).hasMatch(r['recipient_masked'] as String) ||
        r['reference'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$',
        ).hasMatch(r['reference'] as String)) {
      successorInvalid();
    }
    for (final key in [
      'closure_id',
      'journal_entry_id',
      'payment_id',
      'collection_id',
      'member_record_id',
    ]) {
      cancelUuid(r[key]);
    }
    for (final key in [
      'transport_proof_sha256',
      'source_sha256',
      'destination_sha256',
      'body_sha256',
    ]) {
      successorHash(r[key]);
    }
    if (sha256.convert(utf8.encode(r['body'] as String)).toString() !=
        r['body_sha256'])
      successorInvalid();
    for (final key in [
      'root_revision',
      'lineage_revision',
      'destination_revision',
      'policy_revision',
      'consent_revision',
    ]) {
      r[key] = cancelRevision(r[key]);
    }
    r['amount_rwf'] = exactJsonInteger(
      r['amount_rwf'],
      field: 'recorded receipt amount',
      minimum: 1,
      maximum: 9007199254740991,
    );
    r['member_balance_recorded_rwf'] = exactJsonInteger(
      r['member_balance_recorded_rwf'],
      field: 'recorded member balance',
      minimum: 0,
      maximum: 9007199254740991,
    );
    r['segment_count'] = exactJsonInteger(
      r['segment_count'],
      field: 'SMS segments',
      minimum: 1,
      maximum: 10,
    );
    cancelInstant(r['snapshot_recorded_at']);
    return AdminReceiptSuccessorPreview._(Map.unmodifiable(r));
  }
}

class AdminReceiptSuccessorInspection {
  AdminReceiptSuccessorInspection._(
    this.row,
    this.preview,
    this.checkedAt,
    this.validUntil,
  );
  final Map<String, dynamic> row;
  final AdminReceiptSuccessorPreview? preview;
  final DateTime checkedAt, validUntil;
  bool get canApprove => row['can_approve'] == true;
  String get reason => row['reason_code'] as String;
  String? get previewHash => row['preview_sha256'] as String?;
  bool fresh(DateTime now) => successorFresh(checkedAt, validUntil, now);
  factory AdminReceiptSuccessorInspection.parse(
    Object? raw,
    String outbox,
    String source,
  ) {
    final r = successorObject(raw, {
      'contract_version',
      'scope',
      'action',
      'outbox_id',
      'source_snapshot_id',
      'checked_at',
      'sample_valid_until',
      'status',
      'can_approve',
      'reason_code',
      'preview',
      'preview_sha256',
      'configuration_enabled',
      'primary_receipt_retained',
      ..._limits,
    });
    _contract(r, retained: true);
    final checked = cancelInstant(r['checked_at']),
        until = cancelInstant(r['sample_valid_until']);
    if (r['outbox_id'] != cancelUuid(outbox) ||
        r['source_snapshot_id'] != cancelUuid(source) ||
        r['action'] != 'retry_uninvoked' ||
        r['can_approve'] is! bool ||
        r['configuration_enabled'] is! bool ||
        until.difference(checked) != const Duration(seconds: 60) ||
        !{
          'unavailable',
          'source_not_original',
          'irreversible_closure_required',
          'transport_proof_changed',
          'source_evidence_invalid',
          'policy_disabled',
          'consent_missing',
          'contact_missing',
          'content_refused',
          'revision_exhausted',
          'retry_eligible',
          'approval_pending',
        }.contains(r['reason_code']) ||
        r['can_approve'] != (r['reason_code'] == 'retry_eligible') ||
        r['status'] !=
            (r['reason_code'] == 'unavailable' ? 'unavailable' : 'available')) {
      successorInvalid();
    }
    final shown = {
      'retry_eligible',
      'approval_pending',
    }.contains(r['reason_code']);
    if ((!shown && r['preview'] != null) ||
        (r['can_approve'] != true && r['preview_sha256'] != null))
      successorInvalid();
    if (r['can_approve'] == true) successorHash(r['preview_sha256']);
    return AdminReceiptSuccessorInspection._(
      Map.unmodifiable(r),
      shown
          ? AdminReceiptSuccessorPreview.parse(r['preview'], outbox, source)
          : null,
      checked,
      until,
    );
  }
}

class AdminReceiptSuccessorBinding {
  AdminReceiptSuccessorBinding({
    required this.requestId,
    required this.action,
    required Map<String, Object?> expected,
  }) : expected = Map.unmodifiable(expected) {
    cancelUuid(requestId);
    if (!{
      'close_unarmed',
      'approve_successor',
      'revoke_successor',
    }.contains(action))
      successorInvalid();
    cancelUuid(this.expected['outbox_id']);
  }
  final String requestId, action;
  final Map<String, Object?> expected;
  Map<String, Object?> encode() => {
    'request_id': requestId,
    'action': action,
    'expected': expected,
  };
  factory AdminReceiptSuccessorBinding.parse(Object? raw) {
    final r = successorObject(raw, {'request_id', 'action', 'expected'});
    if (r['expected'] is! Map) successorInvalid();
    final action = r['action'];
    final keys = switch (action) {
      'close_unarmed' => {
        'outbox_id',
        'expected_root_revision',
        'expected_lineage_revision',
      },
      'approve_successor' => {
        'outbox_id',
        'source_snapshot_id',
        'expected_root_revision',
        'expected_lineage_revision',
        'preview_sha256',
      },
      'revoke_successor' => {
        'outbox_id',
        'approval_id',
        'expected_lineage_revision',
      },
      _ => successorInvalid(),
    };
    final e = successorObject(r['expected'], keys);
    for (final key in keys) {
      if (key.endsWith('_id'))
        cancelUuid(e[key]);
      else if (key.endsWith('_revision'))
        cancelRevision(e[key]);
      else
        successorHash(e[key]);
    }
    return AdminReceiptSuccessorBinding(
      requestId: cancelUuid(r['request_id']),
      action: action as String,
      expected: Map<String, Object?>.from(e),
    );
  }
}

class AdminReceiptSuccessorReceipt {
  AdminReceiptSuccessorReceipt._(this.row, this.recordedAt);
  final Map<String, dynamic> row;
  final DateTime recordedAt;
  String get action => row['action'] as String;
  String? get approvalId => row['approval_id'] as String?;
  int get lineageRevision => row['lineage_revision'] as int;
  factory AdminReceiptSuccessorReceipt.parse(
    Object? raw,
    AdminReceiptSuccessorBinding binding,
  ) {
    final common = {
      'contract_version',
      'scope',
      'action',
      'request_id',
      'outbox_id',
      'expected_lineage_revision',
      'lineage_revision',
      'recorded_at',
      'primary_receipt_retained',
      ..._limits,
    };
    final extra = switch (binding.action) {
      'close_unarmed' => {
        'closure_id',
        'expected_root_revision',
        'root_revision',
        'proof_class',
        'proof_sha256',
        'reason_code',
      },
      'approve_successor' => {
        'approval_id',
        'sequence',
        'successor_action',
        'source_snapshot_id',
        'expected_root_revision',
        'preview_sha256',
        'reason_code',
        'expires_at',
      },
      'revoke_successor' => {'approval_id'},
      _ => successorInvalid(),
    };
    final r = successorObject(raw, {...common, ...extra});
    _contract(r, retained: true);
    if (r['request_id'] != binding.requestId ||
        r['action'] != binding.action ||
        binding.expected.entries.any((e) => r[e.key] != e.value))
      successorInvalid();
    r['lineage_revision'] = cancelRevision(r['lineage_revision']);
    if (r['lineage_revision'] != (r['expected_lineage_revision'] as int) + 1)
      successorInvalid();
    final at = cancelInstant(r['recorded_at']);
    if (binding.action == 'close_unarmed') {
      cancelUuid(r['closure_id']);
      successorHash(r['proof_sha256']);
      if (r['proof_class'] != 'never_armed_closed' ||
          r['reason_code'] != 'definitely_not_invoked' ||
          r['root_revision'] != (r['expected_root_revision'] as int) + 1)
        successorInvalid();
    } else if (binding.action == 'approve_successor') {
      cancelUuid(r['approval_id']);
      r['sequence'] = cancelRevision(r['sequence']);
      if (r['successor_action'] != 'retry_uninvoked' ||
          r['reason_code'] != 'definitely_not_invoked' ||
          cancelInstant(r['expires_at']).difference(at) !=
              const Duration(minutes: 15))
        successorInvalid();
    } else {
      cancelUuid(r['approval_id']);
    }
    return AdminReceiptSuccessorReceipt._(Map.unmodifiable(r), at);
  }
}

class AdminReceiptSuccessorLookup {
  AdminReceiptSuccessorLookup._(this.status, this.receipt);
  final String status;
  final AdminReceiptSuccessorReceipt? receipt;
  factory AdminReceiptSuccessorLookup.parse(
    Object? raw,
    AdminReceiptSuccessorBinding binding,
  ) {
    final r = successorObject(raw, {
      'contract_version',
      'scope',
      'request_id',
      'status',
      'receipt',
    });
    if (r['contract_version'] is! int ||
        r['contract_version'] != 1 ||
        r['scope'] != 'rw_receipt_successors' ||
        r['request_id'] != binding.requestId ||
        !{'recorded', 'in_progress', 'not_recorded'}.contains(r['status']))
      successorInvalid();
    if (r['status'] != 'recorded' && r['receipt'] != null) successorInvalid();
    return AdminReceiptSuccessorLookup._(
      r['status'] as String,
      r['status'] == 'recorded'
          ? AdminReceiptSuccessorReceipt.parse(r['receipt'], binding)
          : null,
    );
  }
}

class AdminReceiptSuccessorApproval {
  AdminReceiptSuccessorApproval._(
    this.row,
    this.preview,
    this.events,
    this.recordedAt,
    this.expiresAt,
  );
  final Map<String, dynamic> row;
  final AdminReceiptSuccessorPreview preview;
  final List<Map<String, dynamic>> events;
  final DateTime recordedAt, expiresAt;
  String get id => row['approval_id'] as String;
  String get status => row['status'] as String;
  int get sequence => row['sequence'] as int;
  int get lineageRevision => row['lineage_revision'] as int;
  factory AdminReceiptSuccessorApproval.parse(Object? raw, String outbox) {
    final r = successorObject(raw, {
      'approval_id',
      'outbox_id',
      'sequence',
      'action',
      'status',
      'preview',
      'preview_sha256',
      'reason_code',
      'reason',
      'recorded_at',
      'expires_at',
      'lineage_revision',
      'events',
    });
    if (r['outbox_id'] != cancelUuid(outbox) ||
        r['action'] != 'retry_uninvoked' ||
        !{'pending', 'expired', 'revoked'}.contains(r['status']) ||
        r['reason_code'] != 'definitely_not_invoked' ||
        r['reason'] is! String ||
        (r['reason'] as String).length < 8 ||
        (r['reason'] as String).length > 500 ||
        r['events'] is! List)
      successorInvalid();
    cancelUuid(r['approval_id']);
    successorHash(r['preview_sha256']);
    r['sequence'] = cancelRevision(r['sequence']);
    r['lineage_revision'] = cancelRevision(r['lineage_revision']);
    final previewRaw = r['preview'];
    if (previewRaw is! Map) successorInvalid();
    final preview = AdminReceiptSuccessorPreview.parse(
      previewRaw,
      outbox,
      cancelUuid(previewRaw['source_snapshot_id']),
    );
    final at = cancelInstant(r['recorded_at']),
        until = cancelInstant(r['expires_at']);
    if (until.difference(at) != const Duration(minutes: 15)) successorInvalid();
    final events = <Map<String, dynamic>>[];
    for (final rawEvent in r['events'] as List) {
      final e = successorObject(rawEvent, {
        'event_id',
        'revision',
        'event_kind',
        'request_id',
        'lineage_revision',
        'reason',
        'recorded_at',
      });
      cancelUuid(e['event_id']);
      cancelUuid(e['request_id']);
      cancelRevision(e['lineage_revision']);
      if (e['revision'] != events.length + 1 ||
          e['event_kind'] != (events.isEmpty ? 'approved' : 'revoked') ||
          e['reason'] is! String ||
          (e['reason'] as String).length < 8 ||
          (e['reason'] as String).length > 500)
        successorInvalid();
      final when = cancelInstant(e['recorded_at']);
      if (when.isBefore(at)) successorInvalid();
      events.add(Map.unmodifiable(e));
    }
    if (events.isEmpty ||
        events.length > 2 ||
        (r['status'] == 'revoked') != (events.length == 2))
      successorInvalid();
    return AdminReceiptSuccessorApproval._(
      Map.unmodifiable(r),
      preview,
      List.unmodifiable(events),
      at,
      until,
    );
  }
}

class AdminReceiptSuccessorHistory {
  AdminReceiptSuccessorHistory._(this.items, this.nextAfter);
  final List<AdminReceiptSuccessorApproval> items;
  final int? nextAfter;
  factory AdminReceiptSuccessorHistory.parse(
    Object? raw,
    String outbox, {
    int? after,
    int limit = 20,
  }) {
    final r = successorObject(raw, {
      'contract_version',
      'scope',
      'outbox_id',
      'items',
      'has_more',
      'next_after',
      ..._limits,
    });
    _contract(r);
    if (r['outbox_id'] != cancelUuid(outbox) ||
        r['items'] is! List ||
        r['has_more'] is! bool ||
        limit < 1 ||
        limit > 50 ||
        (r['items'] as List).length > limit)
      successorInvalid();
    final items = <AdminReceiptSuccessorApproval>[];
    var sequence = after ?? 0;
    final ids = <String>{};
    for (final row in r['items'] as List) {
      final item = AdminReceiptSuccessorApproval.parse(row, outbox);
      if (item.sequence <= sequence || !ids.add(item.id)) successorInvalid();
      sequence = item.sequence;
      items.add(item);
    }
    if (r['has_more'] == true) {
      if (items.length != limit || r['next_after'] != sequence)
        successorInvalid();
    } else if (r['next_after'] != null) {
      successorInvalid();
    }
    return AdminReceiptSuccessorHistory._(
      List.unmodifiable(items),
      r['has_more'] == true ? cancelRevision(r['next_after']) : null,
    );
  }
}
