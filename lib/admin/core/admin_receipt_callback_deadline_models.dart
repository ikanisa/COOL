import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_successor_models.dart';

Never deadlineInvalid() => throw const FormatException(
  'Callback deadline evidence could not be validated.',
);
Map<String, dynamic> _object(Object? raw, Set<String> keys) =>
    successorObject(raw, keys);
int _int(Object? value, [int minimum = 0, int maximum = 1000000000]) =>
    exactJsonInteger(
      value,
      field: 'callback deadline integer',
      minimum: minimum,
      maximum: maximum,
    );
bool _bool(Object? value) {
  if (value is! bool) deadlineInvalid();
  return value;
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    deadlineInvalid();
  }
  return value;
}

Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, dynamic>.unmodifiable(
    value.map((k, v) => MapEntry(k as String, _freeze(v))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
const deadlineFamilies = {'primary_v2', 'receipt_successor'};
const deadlineRules = {'SEND_OUTCOME_UNKNOWN', 'DELIVERY_CALLBACK_GAP'};
const _limits = {
  'financial_action',
  'send_action',
  'carrier_proof',
  'delivery_proven',
};
void _contract(Map<String, dynamic> r, String scope) {
  if (r['contract_version'] is! int ||
      r['contract_version'] != 1 ||
      r['scope'] != scope ||
      _limits.any((k) => r[k] != false)) {
    deadlineInvalid();
  }
  if (cancelInstant(
        r['sample_valid_until'],
      ).difference(cancelInstant(r['checked_at'])) !=
      const Duration(seconds: 60)) {
    deadlineInvalid();
  }
}

String _family(Object? value) {
  if (value is! String || !deadlineFamilies.contains(value)) deadlineInvalid();
  return value;
}

void _source(Object? raw, String family) {
  final r = _object(raw, {
    'expected_segments',
    'sent_covered',
    'delivery_covered',
    'conflict',
    'failure',
    'sticky_uncertainty',
    'causal',
  });
  final count = _int(r['expected_segments'], 1, 10);
  _int(r['sent_covered'], 0, count);
  _int(r['delivery_covered'], 0, count);
  for (final k in ['conflict', 'failure', 'sticky_uncertainty']) {
    _bool(r[k]);
  }
  if (family == 'receipt_successor' && r['sticky_uncertainty'] != false) {
    deadlineInvalid();
  }
  final c = _object(r['causal'], {
    'request_id',
    'recorded_at',
    'lineage_revision',
  });
  if ((c['request_id'] == null) != (c['recorded_at'] == null)) {
    deadlineInvalid();
  }
  if (c['request_id'] != null) {
    cancelUuid(c['request_id']);
    cancelInstant(c['recorded_at']);
  }
  if (family == 'primary_v2' && c['lineage_revision'] != null ||
      c['request_id'] == null && c['lineage_revision'] != null) {
    deadlineInvalid();
  }
  if (family == 'receipt_successor' && c['request_id'] != null) {
    _int(c['lineage_revision'], 2);
  }
}

class CallbackDeadlineCursor {
  CallbackDeadlineCursor(this.beforeAt, this.caseId, this.queryHash) {
    cancelInstant(beforeAt);
    cancelUuid(caseId);
    _hash(queryHash);
  }
  final String beforeAt, caseId, queryHash;
  factory CallbackDeadlineCursor.parse(Object? raw) {
    final r = _object(raw, {'before_at', 'before_case_id', 'query_sha256'});
    return CallbackDeadlineCursor(
      r['before_at'] as String,
      r['before_case_id'] as String,
      r['query_sha256'] as String,
    );
  }
}

class CallbackDeadlineQuery {
  CallbackDeadlineQuery({
    this.family = 'primary_v2',
    this.active,
    this.limit = 20,
    this.cursor,
  }) {
    _family(family);
    _int(limit, 1, 25);
    if (cursor != null && cursor!.queryHash != queryHash) deadlineInvalid();
  }
  final String family;
  final bool? active;
  final int limit;
  final CallbackDeadlineCursor? cursor;
  String get queryHash => sha256
      .convert(
        utf8.encode('[${jsonEncode(family)}, ${jsonEncode(active)}, $limit]'),
      )
      .toString();
  Map<String, dynamic> get parameters => {
    'p_protocol_family': family,
    'p_active': active,
    'p_limit': limit,
    'p_before_at': cursor?.beforeAt,
    'p_before_case_id': cursor?.caseId,
    'p_cursor_query_sha256': cursor?.queryHash,
  };
}

class CallbackDeadlineRow {
  CallbackDeadlineRow._(this.row);
  final Map<String, dynamic> row;
  String get id => row['case_id'] as String;
  String get family => row['protocol_family'] as String;
  String get rule => row['rule_code'] as String;
  String get root => row['root_receipt_id'] as String;
  String? get approval => row['approval_id'] as String?;
  String? get exception => row['exception_id'] as String?;
  int get revision => row['revision'] as int;
  bool get active => row['active'] as bool;
  bool get pending => row['refresh_pending'] as bool;
  String get receiptPath =>
      '/admin/sms-receipts/$root${approval == null ? '' : '?successor_approval=$approval'}';
  factory CallbackDeadlineRow.parse(Object? raw) {
    final r = _object(raw, {
      'case_id',
      'rule_code',
      'protocol_family',
      'root_receipt_id',
      'attempt_id',
      'approval_id',
      'arm_request_id',
      'armed_at',
      'due_at',
      'revision',
      'episode',
      'active',
      'observed_at',
      'source',
      'exception_id',
      'refresh_pending',
    });
    for (final k in [
      'case_id',
      'root_receipt_id',
      'attempt_id',
      'arm_request_id',
    ]) {
      cancelUuid(r[k]);
    }
    final family = _family(r['protocol_family']);
    if (!deadlineRules.contains(r['rule_code'])) deadlineInvalid();
    if (family == 'primary_v2' && r['approval_id'] != null ||
        family == 'receipt_successor' && r['approval_id'] == null) {
      deadlineInvalid();
    }
    if (r['approval_id'] != null) cancelUuid(r['approval_id']);
    if (r['exception_id'] != null) cancelUuid(r['exception_id']);
    final rev = _int(r['revision'], 1);
    _int(r['episode'], 1, rev);
    _bool(r['active']);
    _bool(r['refresh_pending']);
    final armed = cancelInstant(r['armed_at']);
    if (cancelInstant(r['due_at']).difference(armed) !=
            Duration(
              seconds: r['rule_code'] == 'SEND_OUTCOME_UNKNOWN' ? 120 : 300,
            ) ||
        cancelInstant(r['observed_at']).isBefore(armed)) {
      deadlineInvalid();
    }
    _source(r['source'], family);
    if (r['active'] == true && r['exception_id'] == null) deadlineInvalid();
    return CallbackDeadlineRow._(_freeze(r) as Map<String, dynamic>);
  }
}

void _worker(Object? raw) {
  if (raw == null) return;
  final r = _object(raw, {
    'contract_version',
    'request_id',
    'configuration_revision',
    'expires_at',
    'telemetry_revision',
    'policy_revision',
    'recorded_at',
    'deadlines',
    'aggregate_status',
    'aggregate_reason',
    'escalation_status',
    'financial_action',
    'send_action',
  });
  if (r['contract_version'] != 1 ||
      r['contract_version'] is! int ||
      r['financial_action'] != false ||
      r['send_action'] != false ||
      r['aggregate_status'] != 'not_admitted' ||
      r['aggregate_reason'] != 'complete_input_plan_closure_unproved' ||
      !{
        'processed',
        'deferred_aggregate_not_admitted',
      }.contains(r['escalation_status'])) {
    deadlineInvalid();
  }
  cancelUuid(r['request_id']);
  for (final k in [
    'configuration_revision',
    'telemetry_revision',
    'policy_revision',
  ]) {
    _int(r[k], 1);
  }
  if (!cancelInstant(
    r['expires_at'],
  ).isAfter(cancelInstant(r['recorded_at']))) {
    deadlineInvalid();
  }
  final d = _object(r['deadlines'], {
    'status',
    'processed',
    'busy',
    'unavailable',
    'partial',
  });
  if (!{
    'inactive',
    'unavailable',
    'partial',
    'processed',
  }.contains(d['status'])) {
    deadlineInvalid();
  }
  if (_int(d['processed'], 0, 25) +
          _int(d['busy'], 0, 25) +
          _int(d['unavailable'], 0, 25) >
      25) {
    deadlineInvalid();
  }
  _bool(d['partial']);
  if ({'inactive', 'unavailable'}.contains(d['status']) &&
      (d['processed'] != 0 ||
          d['busy'] != 0 ||
          d['unavailable'] != 0 ||
          d['partial'] != true)) {
    deadlineInvalid();
  }
}

class CallbackDeadlinePage {
  CallbackDeadlinePage._(this.row, this.items, this.next);
  final Map<String, dynamic> row;
  final List<CallbackDeadlineRow> items;
  final CallbackDeadlineCursor? next;
  DateTime get checkedAt => cancelInstant(row['checked_at']);
  DateTime get validUntil => cancelInstant(row['sample_valid_until']);
  bool fresh(DateTime now) => successorFresh(checkedAt, validUntil, now);
  bool get enabled => row['publication_enabled'] as bool;
  factory CallbackDeadlinePage.parse(Object? raw, CallbackDeadlineQuery query) {
    final r = _object(raw, {
      'contract_version',
      'scope',
      'protocol_family',
      'active_filter',
      'limit',
      'query_sha256',
      'checked_at',
      'sample_valid_until',
      'status',
      'rows',
      'scanned_count',
      'next_cursor',
      'seed_progress',
      'publication_enabled',
      'last_worker',
      'financial_action',
      'send_action',
      'carrier_proof',
      'delivery_proven',
    });
    _contract(r, 'receipt_callback_deadlines');
    if (r['protocol_family'] != query.family ||
        r['active_filter'] != query.active ||
        r['limit'] != query.limit ||
        _hash(r['query_sha256']) != query.queryHash ||
        r['status'] != 'available') {
      deadlineInvalid();
    }
    final rawRows = r['rows'];
    if (rawRows is! List ||
        rawRows.length > query.limit ||
        _int(r['scanned_count'], 0, query.limit) != rawRows.length) {
      deadlineInvalid();
    }
    final items = rawRows.map(CallbackDeadlineRow.parse).toList();
    final seen = <String>{};
    CallbackDeadlineRow? prior;
    for (final item in items) {
      if (item.family != query.family ||
          query.active != null && item.active != query.active ||
          !seen.add(item.id)) {
        deadlineInvalid();
      }
      final at = cancelInstant(item.row['armed_at']);
      final before = prior == null
          ? query.cursor?.beforeAt
          : prior.row['armed_at'] as String;
      final beforeId = prior == null ? query.cursor?.caseId : prior.id;
      if (before != null &&
          (at.isAfter(cancelInstant(before)) ||
              at == cancelInstant(before) &&
                  item.id.compareTo(beforeId!) >= 0)) {
        deadlineInvalid();
      }
      prior = item;
    }
    final next = r['next_cursor'] == null
        ? null
        : CallbackDeadlineCursor.parse(r['next_cursor']);
    if (next != null &&
        (items.length != query.limit ||
            next.queryHash != query.queryHash ||
            next.caseId != items.last.id ||
            next.beforeAt != items.last.row['armed_at'])) {
      deadlineInvalid();
    }
    final progress = r['seed_progress'];
    if (progress is! List || progress.length != 2) deadlineInvalid();
    final families = <String>{};
    for (final raw in progress) {
      final s = _object(raw, {
        'protocol_family',
        'after_at',
        'after_attempt_id',
        'exhausted',
      });
      if (!families.add(_family(s['protocol_family'])) ||
          (s['after_at'] == null) != (s['after_attempt_id'] == null)) {
        deadlineInvalid();
      }
      if (s['after_at'] != null) {
        cancelInstant(s['after_at']);
        cancelUuid(s['after_attempt_id']);
      }
      _bool(s['exhausted']);
    }
    _bool(r['publication_enabled']);
    _worker(r['last_worker']);
    return CallbackDeadlinePage._(
      _freeze(r) as Map<String, dynamic>,
      List.unmodifiable(items),
      next,
    );
  }
}

class CallbackDeadlineDetail {
  CallbackDeadlineDetail._(this.row, this.head);
  final Map<String, dynamic> row;
  final CallbackDeadlineRow? head;
  int? get cutoff => row['cutoff_revision'] as int?;
  int? get next => row['next_revision'] as int?;
  bool fresh(DateTime now) => successorFresh(
    cancelInstant(row['checked_at']),
    cancelInstant(row['sample_valid_until']),
    now,
  );
  factory CallbackDeadlineDetail.parse(
    Object? raw,
    String id, {
    int? cutoff,
    int? after,
    int limit = 20,
  }) {
    cancelUuid(id);
    _int(limit, 1, 25);
    if ((cutoff == null) != (after == null)) deadlineInvalid();
    final r = _object(raw, {
      'contract_version',
      'scope',
      'case_id',
      'cutoff_revision',
      'after_revision',
      'limit',
      'checked_at',
      'sample_valid_until',
      'status',
      'head',
      'items',
      'scanned_count',
      'next_revision',
      'financial_action',
      'send_action',
      'carrier_proof',
      'delivery_proven',
    });
    _contract(r, 'receipt_callback_deadline_detail');
    if (r['case_id'] != id ||
        r['after_revision'] != after ||
        r['limit'] != limit ||
        !{'available', 'unavailable'}.contains(r['status'])) {
      deadlineInvalid();
    }
    final head = r['head'] == null
        ? null
        : CallbackDeadlineRow.parse(r['head']);
    final rows = r['items'];
    if (rows is! List ||
        rows.length > limit ||
        _int(r['scanned_count'], 0, limit) != rows.length) {
      deadlineInvalid();
    }
    if (r['status'] == 'unavailable') {
      if (head != null ||
          rows.isNotEmpty ||
          r['next_revision'] != null ||
          cutoff == null && r['cutoff_revision'] != null) {
        deadlineInvalid();
      }
    } else {
      if (head == null || head.id != id) deadlineInvalid();
      final bound = _int(r['cutoff_revision'], 1, head.revision);
      if (cutoff != null && bound != cutoff) deadlineInvalid();
      int previous = after ?? 0;
      for (final raw in rows) {
        final o = _object(raw, {
          'revision',
          'active',
          'episode',
          'source_sha256',
          'source',
          'observed_at',
        });
        final revision = _int(o['revision'], previous + 1, bound);
        _int(o['episode'], 1, revision);
        _bool(o['active']);
        _hash(o['source_sha256']);
        _source(o['source'], head.family);
        if (cancelInstant(
          o['observed_at'],
        ).isBefore(cancelInstant(head.row['armed_at']))) {
          deadlineInvalid();
        }
        previous = revision;
      }
      if (r['next_revision'] != null &&
          (rows.length != limit ||
              _int(r['next_revision'], 1, bound) != previous ||
              previous >= bound)) {
        deadlineInvalid();
      }
    }
    return CallbackDeadlineDetail._(_freeze(r) as Map<String, dynamic>, head);
  }
}

String? deadlineApprovalFromUri(Uri uri) {
  final values = uri.queryParametersAll['successor_approval'];
  if (values == null) return null;
  if (values.length != 1) deadlineInvalid();
  return cancelUuid(values.single);
}
