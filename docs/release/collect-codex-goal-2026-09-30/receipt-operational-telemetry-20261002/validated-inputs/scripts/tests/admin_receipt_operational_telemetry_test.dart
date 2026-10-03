import 'dart:convert';
import 'dart:io';

import '../../lib/admin/core/admin_exception_models.dart';
import '../../lib/admin/core/admin_exception_workflow_models.dart';
import '../../lib/admin/core/admin_receipt_operational_telemetry.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError(
      'Provide an actual SQL fixture directory or --boundaries',
    );
  }
  var checks = 0;
  void check(String name, bool condition) {
    if (!condition) throw StateError(name);
    checks++;
    stdout.writeln('PASS $name');
  }

  void denied(String name, void Function() action) {
    var rejected = false;
    try {
      action();
    } on FormatException {
      rejected = true;
    }
    check(name, rejected);
  }

  const id = '997a0000-0000-4000-8000-000000000001';
  const checked = '2026-10-01T10:00:00.000000Z';
  final base = <String, dynamic>{
    'contract_version': 1,
    'scope': 'receipt_operations_configured_collections',
    'checked_at': checked,
    'sample_valid_until': '2026-10-01T10:01:00.000000Z',
    'window_start': '2026-09-30T10:00:00.000000Z',
    'window_end': checked,
    'window_seconds': 86400,
    'policy_revision': 1,
    'mode': 'Paused',
    'emergency_stop': true,
    'configured_collection_count': 1,
    'backlog': {
      'unhandled_events': 1,
      'oldest_unhandled_age_seconds': 300,
      'due_deferrals': 1,
      'source_busy_deferrals': 1,
    },
    'handling': {
      'events_created_24h': 0,
      'events_handled_24h': 1,
      'latency_p50_ms': 120000,
      'latency_p95_ms': 120000,
      'latency_max_ms': 120000,
    },
    'budgets': {
      'scope': 'global_utc_day',
      'utc_day_start': '2026-10-01T00:00:00.000000Z',
      'actions_reserved': 2,
      'actions_cap': 1,
      'sms_segments_reserved': 2,
      'sms_segments_cap': 1,
    },
    'callbacks': {
      'armed_attempts_24h': 1,
      'expected_segments': 2,
      'covered_sent_segments': 2,
      'covered_delivery_segments': 1,
      'complete_delivery_callback_attempts': 0,
      'conflicting_attempts': 0,
    },
    'unknown': {
      'uncertain_attempts': 1,
      'started_without_all_sent_callbacks': 0,
      'observed_sent_without_all_delivery_callbacks': 1,
      'callback_conflict_attempts': 0,
    },
    'alerts': [
      {
        'id': id,
        'rule_code': 'BACKLOG_AGED',
        'status': 'active',
        'episode': 1,
        'revision': 1,
        'source_kind': 'business_event',
        'source_id': id,
        'exception_id': id,
        'response_code': 'investigate_backlog',
        'observed_at': checked,
      },
    ],
    'evidence_limit_codes': AdminReceiptOperationalTelemetry
        .requiredEvidenceLimitCodes
        .toList(),
    'financial_action': false,
    'send_action': false,
  };
  final valid = AdminReceiptOperationalTelemetry.parse(base);
  check(
    'boundary sample distinguishes handling, budget and callback observations',
    valid.measurementAvailable &&
        valid.handling!['events_created_24h'] == 0 &&
        valid.handling!['events_handled_24h'] == 1 &&
        valid.budgets!['actions_reserved'] == 2 &&
        valid.callbacks!['covered_delivery_segments'] == 1 &&
        valid.alerts.single.responseCode == 'investigate_backlog',
  );
  check(
    'sample expiry and checked time are enforced independently',
    valid.isFresh(valid.checkedAt) &&
        !valid.isFresh(
          valid.checkedAt.subtract(const Duration(microseconds: 1)),
        ) &&
        !valid.isFresh(valid.validUntil),
  );
  void mutate(String name, void Function(Map<String, dynamic>) patch) {
    final value = _copy(base);
    patch(value);
    denied(name, () => AdminReceiptOperationalTelemetry.parse(value));
  }

  mutate(
    'private destination cannot enter the closed top-level DTO',
    (d) => d['destination'] = '+250788000000',
  );
  mutate(
    'missing section cannot be treated as zero',
    (d) => d.remove('unknown'),
  );
  mutate(
    'unknown limit code refuses a fabricated evidence claim',
    (d) => (d['evidence_limit_codes'] as List).add('carrier_delivery_proven'),
  );
  mutate(
    'duplicate fixed evidence codes refuse',
    (d) => (d['evidence_limit_codes'] as List).add('costs_unmeasured'),
  );
  mutate(
    'fixed evidence limits are mandatory',
    (d) => (d['evidence_limit_codes'] as List).remove('costs_unmeasured'),
  );
  mutate(
    'out-of-range JSON integer refuses before use',
    (d) => d['backlog']['unhandled_events'] = 9007199254740992,
  );
  mutate(
    'floating JSON count refuses',
    (d) => d['backlog']['unhandled_events'] = 1.0,
  );
  mutate(
    'negative count refuses',
    (d) => d['unknown']['uncertain_attempts'] = -1,
  );
  mutate(
    'impossible calendar dates refuse',
    (d) => d['checked_at'] = '2026-02-30T10:00:00.000000Z',
  );
  mutate(
    'naive timestamp refuses',
    (d) => d['checked_at'] = '2026-10-01T10:00:00.000000',
  );
  mutate(
    'window end must identify the same snapshot',
    (d) => d['window_end'] = '2026-10-01T10:00:01.000000Z',
  );
  mutate(
    'window must be exactly twenty-four hours',
    (d) => d['window_start'] = '2026-09-30T10:00:01.000000Z',
  );
  mutate(
    'sample validity must be exactly sixty seconds',
    (d) => d['sample_valid_until'] = '2026-10-01T10:01:01.000000Z',
  );
  mutate(
    'global budget day must match snapshot UTC day',
    (d) => d['budgets']['utc_day_start'] = '2026-09-30T00:00:00.000000Z',
  );
  mutate(
    'paused policy requires emergency stop',
    (d) => d['emergency_stop'] = false,
  );
  mutate(
    'financial side effects cannot be claimed',
    (d) => d['financial_action'] = true,
  );
  mutate('send side effects cannot be claimed', (d) => d['send_action'] = true);
  mutate(
    'nonempty backlog requires an actual age',
    (d) => d['backlog']['oldest_unhandled_age_seconds'] = null,
  );
  mutate(
    'zero backlog cannot retain an age',
    (d) => d['backlog']['unhandled_events'] = 0,
  );
  mutate(
    'deferrals cannot exceed pending business events',
    (d) => d['backlog']['due_deferrals'] = 2,
  );
  mutate(
    'handled cohort requires a latency observation',
    (d) => d['handling']['latency_p50_ms'] = null,
  );
  mutate(
    'latency percentiles cannot be reordered',
    (d) => d['handling']['latency_p50_ms'] = 120001,
  );
  mutate(
    'callback coverage cannot exceed the expected multipart plan',
    (d) => d['callbacks']['covered_delivery_segments'] = 3,
  );
  mutate(
    'an armed attempt cannot have no expected segments',
    (d) => d['callbacks']['expected_segments'] = 0,
  );
  mutate(
    'unknown alert code refuses',
    (d) => d['alerts'][0]['rule_code'] = 'DELIVERY_SUCCEEDED',
  );
  mutate(
    'alert response must match its closed rule',
    (d) => d['alerts'][0]['response_code'] = 'reconcile_unknown',
  );
  mutate(
    'nonpolicy alerts require an actual source UUID',
    (d) => d['alerts'][0]['source_id'] = null,
  );
  mutate(
    'future alert observations refuse',
    (d) => d['alerts'][0]['observed_at'] = '2026-10-01T10:00:00.000001Z',
  );
  mutate('zero alert episode refuses', (d) => d['alerts'][0]['episode'] = 0);
  mutate(
    'duplicate alert rules refuse',
    (d) => (d['alerts'] as List).add(_copy(d['alerts'][0])),
  );
  mutate(
    'unavailable code cannot accompany apparent zero/healthy metrics',
    (d) => (d['evidence_limit_codes'] as List).add('measurement_timeout'),
  );
  final empty = _copy(base)..['configured_collection_count'] = 0;
  for (final key in [
    'backlog',
    'handling',
    'budgets',
    'callbacks',
    'unknown',
  ]) {
    empty[key] = null;
  }
  (empty['evidence_limit_codes'] as List).add('no_configured_scope');
  final unknown = AdminReceiptOperationalTelemetry.parse(empty);
  check(
    'unconfigured sample preserves prior alert without inventing clearance',
    !unknown.measurementAvailable &&
        unknown.alerts.single.status == 'active' &&
        unknown.budgets == null,
  );
  final zero = _copy(base)..['alerts'] = [];
  zero['backlog'] = {
    'unhandled_events': 0,
    'oldest_unhandled_age_seconds': null,
    'due_deferrals': 0,
    'source_busy_deferrals': 0,
  };
  zero['handling'] = {
    'events_created_24h': 0,
    'events_handled_24h': 0,
    'latency_p50_ms': null,
    'latency_p95_ms': null,
    'latency_max_ms': null,
  };
  check(
    'empty valid cohort retains nullable ages and latencies',
    AdminReceiptOperationalTelemetry.parse(zero).measurementAvailable,
  );
  final workflow = <String, dynamic>{
    'contract_version': 1,
    'exception_id': id,
    'source_revision': 2,
    'source_active': false,
    'workflow_revision': 0,
    'assignee_id': null,
    'recipient_available': false,
    'due_at': null,
    'overdue': false,
    'status': 'superseded',
    'escalations': [],
    'checked_at': checked,
    'sample_valid_until': '2026-10-01T10:01:00.000000Z',
  };
  check(
    'superseded workflow is retained independently from resolution',
    AdminExceptionWorkflow.parse(workflow, id).status == 'superseded',
  );
  denied(
    'superseded workflow cannot remain an active source',
    () =>
        AdminExceptionWorkflow.parse({...workflow, 'source_active': true}, id),
  );
  check(
    'source-busy predecessor label is preserved',
    adminExceptionReasonLabel(
          AdminExceptionSource.receiptEvent,
          'RECEIPT_OPERATION_SOURCE_BUSY',
        ) ==
        'Receipt source is busy',
  );
  for (final rule in AdminReceiptOperationalTelemetry.ruleLabels.keys) {
    final row = <String, dynamic>{
      'id': id,
      'source_kind': 'receipt_telemetry',
      'source_id': id,
      'reason_code': 'TELEMETRY_$rule',
      'active': true,
      'revision': 1,
      'source_sha256': List.filled(64, 'a').join(),
      'first_observed_at': checked,
      'last_changed_at': checked,
      'transaction_sms_id': null,
      'acknowledged': false,
      'escalation_requested': false,
    };
    final model = AdminExceptionRow.parse(row, exceptionInstant(checked));
    check(
      'finite telemetry reason $rule stays separate from a financial route',
      model.source == AdminExceptionSource.receiptTelemetry &&
          model.reasonLabel ==
              AdminReceiptOperationalTelemetry.ruleLabels[rule] &&
          model.investigationPath == null &&
          !model.source.isReceiptDeferral,
    );
    denied(
      'telemetry reason $rule cannot invent a transaction link',
      () => AdminExceptionRow.parse({
        ...row,
        'transaction_sms_id': id,
      }, exceptionInstant(checked)),
    );
    denied(
      'telemetry reason $rule cannot attach to an unrelated source kind',
      () => AdminExceptionRow.parse({
        ...row,
        'source_kind': 'payment',
      }, exceptionInstant(checked)),
    );
  }
  if (args.single == '--boundaries') {
    stdout.writeln(
      'PASS $checks distinct hand-built boundary checks; no SQL fixture claim',
    );
    return;
  }

  Map<String, dynamic> read(String name) => Map<String, dynamic>.from(
    jsonDecode(File('${args.single}/$name').readAsStringSync()) as Map,
  );
  final index = exceptionObject(read('fixture-index.json'), {
    'telemetry',
    'exception_inbox',
    'workflow',
  });
  List<String> files(String key) {
    final value = index[key];
    if (value is! List ||
        value.isEmpty ||
        value.any(
          (name) =>
              name is! String || !RegExp(r'^[a-z0-9_-]+\.json$').hasMatch(name),
        )) {
      throw StateError('Invalid actual SQL fixture index');
    }
    return value.cast<String>();
  }

  var active = false, unavailable = false, superseded = false;
  final reasons = <String>{};
  for (final name in files('telemetry')) {
    final observed = AdminReceiptOperationalTelemetry.parse(read(name));
    active |= observed.alerts.any((alert) => alert.status == 'active');
    unavailable |= !observed.measurementAvailable;
    check(
      'actual SQL telemetry $name decodes without inferred delivery',
      observed.evidenceLimitCodes.contains(
        'callback_coverage_not_delivery_success',
      ),
    );
  }
  for (final name in files('exception_inbox')) {
    final raw = read(name), source = raw['source_kind'];
    final page = AdminExceptionSnapshot.parse(
      raw,
      active: raw['active'] as bool,
      limit: raw['limit'] as int,
      source: source == null ? null : AdminExceptionSource.parse(source),
    );
    for (final row in page.rows.where(
      (row) => row.source == AdminExceptionSource.receiptTelemetry,
    )) {
      reasons.add(row.reasonCode);
      check(
        'actual telemetry exception ${row.reasonCode} has no financial route',
        row.transactionSmsId == null && row.investigationPath == null,
      );
    }
  }
  for (final name in files('workflow')) {
    final raw = read(name),
        model = AdminExceptionWorkflow.parse(
          raw,
          raw['exception_id'] as String,
        );
    superseded |= model.status == 'superseded';
    check(
      'actual SQL workflow $name retains source disposition',
      model.status != 'superseded' || !model.sourceActive,
    );
  }
  check(
    'actual SQL inputs include an active alert and unavailable sample',
    active && unavailable,
  );
  check(
    'actual SQL inputs cover all six finite telemetry reasons',
    reasons.length == 6 &&
        AdminReceiptOperationalTelemetry.ruleLabels.keys.every(
          (rule) => reasons.contains('TELEMETRY_$rule'),
        ),
  );
  check('actual SQL inputs include explicit superseded workflow', superseded);
  stdout.writeln(
    'PASS $checks distinct Admin model checks including actual SQL fixtures',
  );
}
