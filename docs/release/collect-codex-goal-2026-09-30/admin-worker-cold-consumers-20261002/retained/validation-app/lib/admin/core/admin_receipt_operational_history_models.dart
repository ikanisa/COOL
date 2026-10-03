import '../../core/data/exact_json_values.dart';

Never historyInvalid() => throw const FormatException(
  'Receipt operational history could not be validated.',
);
Map<String, dynamic> historyObject(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((k) => k is! String || !keys.contains(k))) {
    historyInvalid();
  }
  return Map<String, dynamic>.from(raw);
}

String historyUuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    historyInvalid();
  }
  return raw;
}

DateTime historyInstant(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    historyInvalid();
  }
  return exactJsonTimestamp(raw, field: 'operational history timestamp');
}

String historyUtc(DateTime value) {
  final d = value.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}.${(d.millisecond * 1000 + d.microsecond).toString().padLeft(6, '0')}Z';
}

int historyCount(Object? raw, {int min = 0, int max = maxExactJsonInteger}) {
  if (raw is! int || raw < min || raw > max) historyInvalid();
  return raw;
}

bool _boolean(Object? raw) {
  if (raw is! bool) historyInvalid();
  return raw;
}

String _choice(Object? raw, Set<String> options) {
  if (raw is! String || !options.contains(raw)) historyInvalid();
  return raw;
}

const historyModes = {'Shadow', 'Dry-run', 'Live-limited', 'Live', 'Paused'};
const historyOutcomeCodes = {
  'SOURCE_CHANGED',
  'SOURCE_SUPERSEDED',
  'PAYMENT_REVERSED',
  'PAYMENT_NOT_POSTED',
  'SNAPSHOT_MISSING',
  'RECIPIENT_INELIGIBLE',
  'POLICY_DISABLED',
  'CONSENT_MISSING',
  'CONTACT_MISSING',
  'CATCHUP_DISABLED',
  'CATCHUP_WINDOW_EXCEEDED',
  'CONTACT_HISTORY_UNPROVEN',
  'POLICY_HISTORY_UNPROVEN',
  'CONSENT_HISTORY_UNPROVEN',
  'CONTENT_REFUSED',
  'DRY_RUN_ELIGIBLE',
  'RECEIPT_ENQUEUED',
  'RECEIPT_EXISTS',
  'SHADOW_OBSERVED',
  'QUOTA_EXHAUSTED',
  'LEGACY_CONTENT_REVIEW_REQUIRED',
  'SOURCE_BUSY',
};
const historyHandledCodes = {
  'RECEIPT_ENQUEUED',
  'RECEIPT_EXISTS',
  'PAYMENT_REVERSED',
  'SOURCE_SUPERSEDED',
};
const historyCapKeys = {
  'run_actions',
  'group_actions',
  'device_actions',
  'global_actions',
  'run_sms_segments',
  'group_sms_segments',
  'device_sms_segments',
  'global_sms_segments',
};
const receiptOperationsPolicyAuditId = '00000000-0000-4000-8000-000000000001';
String adminReceiptOperationalRunPath(String id) =>
    '/admin/automations/runs/${historyUuid(id)}';

enum AdminReceiptHistorySection {
  events('events', 'Business events'),
  backlogResults('backlog_results', 'Backlog outcomes'),
  budgetRefusals('budget_refusals', 'Backlog budget refusals'),
  reservations('reservations', 'Shared quota reservations');

  const AdminReceiptHistorySection(this.wire, this.label);
  final String wire, label;
}

class AdminReceiptHistoryCursor {
  const AdminReceiptHistoryCursor(this.recordedAt, this.evidenceId);
  final DateTime recordedAt;
  final String evidenceId;
  int compareTo(AdminReceiptHistoryCursor other) {
    final n = recordedAt.compareTo(other.recordedAt);
    return n == 0 ? evidenceId.compareTo(other.evidenceId) : n;
  }

  void validate({AdminReceiptHistorySection? section}) {
    historyInstant(historyUtc(recordedAt));
    if (section == AdminReceiptHistorySection.budgetRefusals) {
      final parts = evidenceId.split(':');
      if (parts.length != 2) historyInvalid();
      for (final p in parts) {
        historyUuid(p);
      }
    } else {
      historyUuid(evidenceId);
    }
  }

  factory AdminReceiptHistoryCursor.parse(
    Object? raw, {
    AdminReceiptHistorySection? section,
  }) {
    final d = historyObject(raw, {'recorded_at', 'evidence_id'});
    final c = AdminReceiptHistoryCursor(
      historyInstant(d['recorded_at']),
      d['evidence_id'] is String
          ? d['evidence_id'] as String
          : historyInvalid(),
    );
    c.validate(section: section);
    return c;
  }
  @override
  bool operator ==(Object other) =>
      other is AdminReceiptHistoryCursor &&
      recordedAt == other.recordedAt &&
      evidenceId == other.evidenceId;
  @override
  int get hashCode => Object.hash(recordedAt, evidenceId);
}

class AdminReceiptHistoryQuery {
  const AdminReceiptHistoryQuery({
    this.runId,
    this.section,
    this.limit = 20,
    this.before,
  });
  final String? runId;
  final AdminReceiptHistorySection? section;
  final int limit;
  final AdminReceiptHistoryCursor? before;
  bool get starts => runId == null;
  void validate() {
    historyCount(limit, min: 1, max: 25);
    if ((runId == null) != (section == null)) historyInvalid();
    if (runId != null) historyUuid(runId);
    before?.validate(section: section);
  }

  Map<String, dynamic> get parameters {
    validate();
    return {
      if (runId != null) 'p_run_id': runId,
      if (section != null) 'p_section': section!.wire,
      'p_limit': limit,
      'p_before_at': before == null ? null : historyUtc(before!.recordedAt),
      starts ? 'p_before_request_id' : 'p_before_id': before?.evidenceId,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AdminReceiptHistoryQuery &&
      runId == other.runId &&
      section == other.section &&
      limit == other.limit &&
      before == other.before;
  @override
  int get hashCode => Object.hash(runId, section, limit, before);
}

class AdminReceiptHistoryRow {
  const AdminReceiptHistoryRow._(this.data, this.cursor);
  final Map<String, dynamic> data;
  final AdminReceiptHistoryCursor cursor;
  String? get runId => data['run_id'] as String?;
  static AdminReceiptHistoryRow parse(
    Object? raw,
    AdminReceiptHistoryQuery query,
    DateTime checked,
  ) {
    Map<String, dynamic> d;
    if (query.starts) {
      d = historyObject(raw, {
        'request_id',
        'principal_id',
        'recorded_at',
        'code',
        'mode',
        'run_id',
        'run_state',
      });
      historyUuid(d['request_id']);
      historyUuid(d['principal_id']);
      if (d['run_id'] != null) historyUuid(d['run_id']);
      _choice(d['code'], {
        'RUN_STARTED',
        'OPERATIONS_PAUSED',
        'PRINCIPAL_SCOPE_UNCONFIGURED',
        'RUN_BUSY',
      });
      _choice(d['mode'], historyModes);
      final state = _choice(d['run_state'], {
        'no_run',
        'unavailable',
        'closed',
        'expired',
        'leased',
      });
      if ((d['code'] == 'RUN_STARTED') == (state == 'no_run') ||
          (d['run_id'] != null) !=
              {'closed', 'expired', 'leased'}.contains(state)) {
        historyInvalid();
      }
    } else if (query.section == AdminReceiptHistorySection.events) {
      d = historyObject(raw, {
        'evidence_id',
        'recorded_at',
        'event_id',
        'source_status',
        'payment_id',
        'transaction_sms_id',
        'receipt_id',
        'exception_ids',
        'assigned_at',
        'outcome',
        'first_handled',
        'current_deferral',
      });
      if (d['evidence_id'] != historyUuid(d['event_id'])) historyInvalid();
      _references(d);
      final assigned = d['assigned_at'] == null
          ? null
          : historyInstant(d['assigned_at']);
      if (assigned?.isAfter(checked) == true) historyInvalid();
      final outcome = d['outcome'] == null
          ? null
          : historyObject(d['outcome'], {
              'source_version',
              'code',
              'business_handled',
              'recorded_at',
            });
      if (outcome != null) {
        historyCount(outcome['source_version'], min: 1, max: 1000000000);
        _choice(outcome['code'], historyOutcomeCodes);
        _boolean(outcome['business_handled']);
        if (historyHandledCodes.contains(outcome['code']) !=
            outcome['business_handled']) {
          historyInvalid();
        }
        if (historyInstant(outcome['recorded_at']).isAfter(checked)) {
          historyInvalid();
        }
      }
      if (assigned == null && outcome == null) historyInvalid();
      final handled = d['first_handled'] == null
          ? null
          : historyObject(d['first_handled'], {
              'run_id',
              'source_version',
              'code',
              'receipt_id',
              'handled_at',
            });
      if (handled != null) {
        historyUuid(handled['run_id']);
        historyCount(handled['source_version'], min: 1, max: 1000000000);
        _choice(handled['code'], historyHandledCodes);
        if (handled['receipt_id'] != null) historyUuid(handled['receipt_id']);
        if (historyInstant(handled['handled_at']).isAfter(checked)) {
          historyInvalid();
        }
      }
      final deferral = d['current_deferral'] == null
          ? null
          : historyObject(d['current_deferral'], {'code', 'next_check_at'});
      if (deferral != null) {
        _choice(deferral['code'], historyOutcomeCodes);
        historyInstant(deferral['next_check_at']);
      }
    } else if (query.section == AdminReceiptHistorySection.reservations) {
      d = historyObject(raw, {
        'evidence_id',
        'recorded_at',
        'collection_id',
        'device_id',
        'fence_version',
        'actions',
        'sms_segments',
        'snapshot_id',
      });
      if (d['snapshot_id'] != null &&
          historyUuid(d['snapshot_id']) != d['evidence_id']) {
        historyInvalid();
      }
      historyUuid(d['collection_id']);
      if (d['device_id'] != null) historyUuid(d['device_id']);
      historyCount(d['fence_version'], min: 1, max: 1000000000);
      final actions = historyCount(d['actions'], max: 1),
          segments = historyCount(d['sms_segments'], max: 10);
      if (actions == 0 && segments == 0) historyInvalid();
    } else {
      d = historyObject(raw, {
        'evidence_id',
        'recorded_at',
        'snapshot_id',
        'request_id',
        'code',
        'business_handled',
        'source_status',
        'payment_id',
        'transaction_sms_id',
        'receipt_id',
        'exception_ids',
      });
      final id = historyUuid(d['snapshot_id']);
      _references(d);
      _choice(d['code'], historyOutcomeCodes);
      _boolean(d['business_handled']);
      if (query.section == AdminReceiptHistorySection.budgetRefusals) {
        final request = historyUuid(d['request_id']);
        if (d['evidence_id'] != '$request:$id' ||
            d['code'] != 'QUOTA_EXHAUSTED' ||
            d['business_handled'] != false ||
            d['receipt_id'] != null) {
          historyInvalid();
        }
      } else if (d['request_id'] != null || d['evidence_id'] != id) {
        historyInvalid();
      }
    }
    final c = AdminReceiptHistoryCursor(
      historyInstant(d['recorded_at']),
      query.starts
          ? d['request_id'] as String
          : d['evidence_id'] is String
          ? d['evidence_id'] as String
          : historyInvalid(),
    );
    c.validate(section: query.section);
    if (c.recordedAt.isAfter(checked)) historyInvalid();
    return AdminReceiptHistoryRow._(_frozen(d), c);
  }

  static void _references(Map<String, dynamic> d) {
    final status = _choice(d['source_status'], {'available', 'unavailable'});
    for (final k in ['payment_id', 'receipt_id', 'transaction_sms_id']) {
      if (d[k] != null) historyUuid(d[k]);
    }
    final ids = d['exception_ids'];
    if (ids is! List || ids.length > 50) historyInvalid();
    final parsed = ids.map(historyUuid).toList();
    if (parsed.toSet().length != parsed.length) historyInvalid();
    if (status == 'unavailable' &&
        (d['payment_id'] != null ||
            d['transaction_sms_id'] != null ||
            d['receipt_id'] != null ||
            ids.isNotEmpty)) {
      historyInvalid();
    }
  }
}

class AdminReceiptHistoryPage {
  const AdminReceiptHistoryPage._(
    this.query,
    this.checkedAt,
    this.validUntil,
    this.available,
    this.rows,
    this.nextCursor,
  );
  final AdminReceiptHistoryQuery query;
  final DateTime checkedAt, validUntil;
  final bool available;
  final List<AdminReceiptHistoryRow> rows;
  final AdminReceiptHistoryCursor? nextCursor;
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
  factory AdminReceiptHistoryPage.parse(
    Object? raw, {
    required AdminReceiptHistoryQuery query,
  }) {
    query.validate();
    final d = historyObject(raw, {
      'contract_version',
      'scope',
      'section',
      'checked_at',
      'sample_valid_until',
      'limit',
      'history_complete',
      'financial_action',
      'send_action',
      'rows',
      'next_cursor',
      if (!query.starts) 'run_id',
      if (!query.starts) 'status',
    });
    _base(d);
    if (d['section'] != (query.section?.wire ?? 'starts') ||
        d['limit'] != query.limit ||
        (!query.starts && d['run_id'] != query.runId)) {
      historyInvalid();
    }
    final checked = historyInstant(d['checked_at']),
        until = historyInstant(d['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      historyInvalid();
    }
    final available =
        query.starts ||
        _choice(d['status'], {'partial', 'unavailable'}) == 'partial';
    final rawRows = d['rows'];
    if (rawRows is! List || rawRows.length > query.limit) historyInvalid();
    final rows = <AdminReceiptHistoryRow>[];
    for (final row in rawRows) {
      final next = AdminReceiptHistoryRow.parse(row, query, checked);
      if (rows.isNotEmpty && next.cursor.compareTo(rows.last.cursor) >= 0 ||
          query.before != null && next.cursor.compareTo(query.before!) >= 0) {
        historyInvalid();
      }
      rows.add(next);
    }
    final next = d['next_cursor'] == null
        ? null
        : AdminReceiptHistoryCursor.parse(
            d['next_cursor'],
            section: query.section,
          );
    if (!available && (rows.isNotEmpty || next != null) ||
        next != null &&
            (rows.length != query.limit || next != rows.last.cursor)) {
      historyInvalid();
    }
    return AdminReceiptHistoryPage._(
      query,
      checked,
      until,
      available,
      List.unmodifiable(rows),
      next,
    );
  }
}

void _base(Map<String, dynamic> d) {
  if (d['contract_version'] is! int ||
      d['contract_version'] != 1 ||
      d['scope'] != 'rw_receipt_operational_history' ||
      d['history_complete'] != false ||
      d['financial_action'] != false ||
      d['send_action'] != false) {
    historyInvalid();
  }
}

class AdminReceiptOperationalRun {
  const AdminReceiptOperationalRun._(
    this.id,
    this.checkedAt,
    this.validUntil,
    this.run,
    this.historicalConfig,
    this.completion,
    this.quotaUsage,
  );
  final String id;
  final DateTime checkedAt, validUntil;
  final Map<String, dynamic>? run, historicalConfig, completion, quotaUsage;
  bool get available => run != null;
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
  factory AdminReceiptOperationalRun.parse(
    Object? raw, {
    required String runId,
  }) {
    historyUuid(runId);
    final d = historyObject(raw, {
      'contract_version',
      'scope',
      'run_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'history_complete',
      'financial_action',
      'send_action',
      'run',
      'historical_config',
      'completion',
      'quota_usage',
    });
    _base(d);
    if (d['run_id'] != runId) historyInvalid();
    final checked = historyInstant(d['checked_at']),
        until = historyInstant(d['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      historyInvalid();
    }
    final available =
        _choice(d['status'], {'partial', 'unavailable'}) == 'partial';
    if (available != (d['run'] != null) ||
        !available &&
            (d['historical_config'] != null ||
                d['completion'] != null ||
                d['quota_usage'] != null)) {
      historyInvalid();
    }
    Map<String, dynamic>? run, config, completion, quota;
    if (available) {
      run = historyObject(d['run'], {
        'request_id',
        'principal_id',
        'fence_version',
        'policy_revision',
        'mode',
        'collection_ids',
        'device_id',
        'started_at',
        'expires_at',
        'completed_at',
        'scan_performed',
        'state',
      });
      historyUuid(run['request_id']);
      historyUuid(run['principal_id']);
      historyCount(run['fence_version'], min: 1, max: 1000000000);
      historyCount(run['policy_revision'], min: 1, max: 1000000000);
      _choice(run['mode'], historyModes.difference({'Paused'}));
      _boolean(run['scan_performed']);
      if (run['device_id'] != null) historyUuid(run['device_id']);
      final ids = run['collection_ids'];
      if (ids is! List || ids.isEmpty || ids.length > 100) historyInvalid();
      final collections = ids.map(historyUuid).toSet();
      if (collections.length != ids.length) historyInvalid();
      final start = historyInstant(run['started_at']),
          expiry = historyInstant(run['expires_at']);
      if (start.isAfter(checked) ||
          !expiry.isAfter(start) ||
          expiry.difference(start) > const Duration(seconds: 120)) {
        historyInvalid();
      }
      final end = run['completed_at'] == null
          ? null
          : historyInstant(run['completed_at']);
      if (end != null && (end.isBefore(start) || end.isAfter(checked))) {
        historyInvalid();
      }
      if (run['state'] !=
          (end != null
              ? 'closed'
              : expiry.isAfter(checked)
              ? 'leased'
              : 'expired')) {
        historyInvalid();
      }
      if (d['historical_config'] != null) {
        config = historyObject(d['historical_config'], {
          'request_id',
          'revision',
          'recorded_at',
          'caps',
        });
        historyUuid(config['request_id']);
        if (config['revision'] != run['policy_revision'] ||
            historyInstant(config['recorded_at']).isAfter(start)) {
          historyInvalid();
        }
        final caps = historyObject(config['caps'], historyCapKeys);
        for (final v in caps.values) {
          historyCount(v, min: 1, max: 1000000);
        }
      }
      if (d['completion'] != null) {
        completion = historyObject(d['completion'], {
          'request_id',
          'recorded_at',
          'handled_count',
          'deferred_count',
          'action_count',
          'sms_segments',
          'business_handled',
        });
        historyUuid(completion['request_id']);
        final at = historyInstant(completion['recorded_at']);
        if (end == null || at.isBefore(end) || at.isAfter(checked)) {
          historyInvalid();
        }
        for (final k in [
          'handled_count',
          'deferred_count',
          'action_count',
          'sms_segments',
        ]) {
          historyCount(completion[k]);
        }
        _boolean(completion['business_handled']);
        if (completion['business_handled'] == true &&
            (run['scan_performed'] != true ||
                completion['deferred_count'] != 0 ||
                !{'Live', 'Live-limited'}.contains(run['mode']))) {
          historyInvalid();
        }
      }
      quota = historyObject(d['quota_usage'], {
        'window_start',
        'window_end',
        'scope',
        'run_actions',
        'run_sms_segments',
        'global_actions',
        'global_sms_segments',
        'device_actions',
        'device_sms_segments',
        'groups',
      });
      if (quota['scope'] != 'immutable_reservations_through_lease_window') {
        historyInvalid();
      }
      final windowStart = historyInstant(quota['window_start']),
          windowEnd = historyInstant(quota['window_end']);
      if (windowStart != DateTime.utc(start.year, start.month, start.day) ||
          windowEnd != (expiry.isBefore(checked) ? expiry : checked)) {
        historyInvalid();
      }
      for (final k in [
        'run_actions',
        'run_sms_segments',
        'global_actions',
        'global_sms_segments',
      ]) {
        historyCount(quota[k]);
      }
      for (final k in ['device_actions', 'device_sms_segments']) {
        if ((run['device_id'] == null) != (quota[k] == null)) historyInvalid();
        if (quota[k] != null) historyCount(quota[k]);
      }
      final groups = quota['groups'];
      if (groups is! List || groups.length != collections.length) {
        historyInvalid();
      }
      final seen = <String>{};
      for (final g in groups) {
        final v = historyObject(g, {
          'collection_id',
          'actions',
          'sms_segments',
        });
        final id = historyUuid(v['collection_id']);
        if (!collections.contains(id) || !seen.add(id)) historyInvalid();
        historyCount(v['actions']);
        historyCount(v['sms_segments']);
      }
    }
    return AdminReceiptOperationalRun._(
      runId,
      checked,
      until,
      run == null ? null : _frozen(run),
      config == null ? null : _frozen(config),
      completion == null ? null : _frozen(completion),
      quota == null ? null : _frozen(quota),
    );
  }
}

Map<String, dynamic> _frozen(Map<String, dynamic> d) =>
    Map.unmodifiable(d.map((k, v) => MapEntry(k, _freeze(v))));
Object? _freeze(Object? v) => v is Map
    ? _frozen(Map<String, dynamic>.from(v))
    : v is List
    ? List.unmodifiable(v.map(_freeze))
    : v;
