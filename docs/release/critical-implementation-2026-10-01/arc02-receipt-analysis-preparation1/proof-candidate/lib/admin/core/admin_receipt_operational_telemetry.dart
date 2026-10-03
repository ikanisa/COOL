import '../../core/data/exact_json_values.dart';

Never _invalid() =>
    throw const FormatException('Invalid receipt operational telemetry.');

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    _invalid();
  }
  return Map<String, dynamic>.from(value);
}

int _count(
  Object? value, {
  int minimum = 0,
  int maximum = maxExactJsonInteger,
}) {
  if (value is! int || value < minimum || value > maximum) _invalid();
  return value;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    _invalid();
  }
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
      ).hasMatch(value)) {
    _invalid();
  }
  return exactJsonTimestamp(value, field: 'receipt telemetry timestamp');
}

/// Retained alert evidence. A cleared or superseded alert does not itself
/// record an operator resolution, and an empty list does not prove clearance.
class AdminReceiptTelemetryAlert {
  const AdminReceiptTelemetryAlert._({
    required this.id,
    required this.ruleCode,
    required this.status,
    required this.episode,
    required this.revision,
    required this.sourceKind,
    required this.sourceId,
    required this.exceptionId,
    required this.responseCode,
    required this.observedAt,
  });
  final String id, ruleCode, status, sourceKind, responseCode;
  final String? sourceId, exceptionId;
  final int episode, revision;
  final DateTime observedAt;
  String get label => AdminReceiptOperationalTelemetry.ruleLabels[ruleCode]!;
  String get responseLabel =>
      AdminReceiptOperationalTelemetry.responseLabels[responseCode]!;

  factory AdminReceiptTelemetryAlert.parse(Object? raw, DateTime checkedAt) {
    final d = _object(raw, {
      'id',
      'rule_code',
      'status',
      'episode',
      'revision',
      'source_kind',
      'source_id',
      'exception_id',
      'response_code',
      'observed_at',
    });
    final rule = d['rule_code'], source = d['source_kind'];
    if (!AdminReceiptOperationalTelemetry.ruleResponses.containsKey(rule) ||
        !{'active', 'clear', 'superseded'}.contains(d['status']) ||
        !{
          'business_event',
          'handled_event',
          'policy',
          'attempt',
        }.contains(source) ||
        d['response_code'] !=
            AdminReceiptOperationalTelemetry.ruleResponses[rule]) {
      _invalid();
    }
    final sourceId = d['source_id'] == null ? null : _uuid(d['source_id']);
    if (source != 'policy' && sourceId == null) _invalid();
    final observed = _instant(d['observed_at']);
    if (observed.isAfter(checkedAt)) _invalid();
    return AdminReceiptTelemetryAlert._(
      id: _uuid(d['id']),
      ruleCode: rule as String,
      status: d['status'] as String,
      episode: _count(d['episode'], minimum: 1, maximum: 1000000000),
      revision: _count(d['revision'], minimum: 1, maximum: 1000000000),
      sourceKind: source as String,
      sourceId: sourceId,
      exceptionId: d['exception_id'] == null ? null : _uuid(d['exception_id']),
      responseCode: d['response_code'] as String,
      observedAt: observed,
    );
  }
}

/// The closed v1 receipt telemetry reader. All five sections are unavailable
/// together; null measurements never become apparent zero or healthy values.
/// This DTO grants no financial, send, retry, or workflow authority.
class AdminReceiptOperationalTelemetry {
  const AdminReceiptOperationalTelemetry._({
    required this.checkedAt,
    required this.validUntil,
    required this.windowStart,
    required this.windowEnd,
    required this.policyRevision,
    required this.mode,
    required this.emergencyStop,
    required this.configuredCollectionCount,
    required this.backlog,
    required this.handling,
    required this.budgets,
    required this.callbacks,
    required this.unknown,
    required this.alerts,
    required this.evidenceLimitCodes,
  });
  final DateTime checkedAt, validUntil, windowStart, windowEnd;
  final int policyRevision, configuredCollectionCount;
  final String mode;
  final bool emergencyStop;
  final Map<String, int?>? backlog, handling;
  final Map<String, dynamic>? budgets;
  final Map<String, int>? callbacks, unknown;
  final List<AdminReceiptTelemetryAlert> alerts;
  final Set<String> evidenceLimitCodes;
  bool get measurementAvailable => backlog != null;
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);

  static const metricLabels = <String, String>{
    'unhandled_events': 'Unhandled business events',
    'oldest_unhandled_age_seconds': 'Oldest unhandled event age',
    'due_deferrals': 'Due deferred events',
    'source_busy_deferrals': 'Events deferred by a busy source',
    'events_created_24h': 'Business events created in 24 hours',
    'events_handled_24h': 'Business events durably handled in 24 hours',
    'latency_p50_ms': 'Durable handling latency, 50th percentile',
    'latency_p95_ms': 'Durable handling latency, 95th percentile',
    'latency_max_ms': 'Maximum durable handling latency',
    'actions_reserved': 'Actions reserved in the UTC day',
    'actions_cap': 'Global daily action budget limit',
    'sms_segments_reserved': 'SMS segments reserved in the UTC day',
    'sms_segments_cap': 'Global daily SMS segment budget limit',
    'armed_attempts_24h': 'Attempts armed in 24 hours',
    'expected_segments': 'Segments expecting callback observations',
    'covered_sent_segments':
        'Segments with consistent sent callback observations',
    'covered_delivery_segments':
        'Segments with consistent delivery callback observations',
    'complete_delivery_callback_attempts':
        'Attempts with complete delivery callback coverage',
    'conflicting_attempts':
        'Armed attempts with conflicting callback observations',
    'uncertain_attempts': 'Attempts with an uncertain recorded outcome',
    'started_without_all_sent_callbacks':
        'Started attempts missing sent callback coverage',
    'observed_sent_without_all_delivery_callbacks':
        'Observed sent attempts missing delivery callback coverage',
    'callback_conflict_attempts':
        'Attempts with conflicting callback observations',
  };
  static const ruleLabels = <String, String>{
    'BACKLOG_AGED': 'Receipt backlog age',
    'HANDLING_LATENCY_HIGH': 'Durable handling latency',
    'ACTION_BUDGET_EXHAUSTED': 'Action budget exhausted',
    'SMS_BUDGET_EXHAUSTED': 'SMS segment budget exhausted',
    'DELIVERY_CALLBACK_GAP': 'Callback observation gap',
    'SEND_OUTCOME_UNKNOWN': 'Unknown send outcome',
  };
  static const ruleResponses = <String, String>{
    'BACKLOG_AGED': 'investigate_backlog',
    'HANDLING_LATENCY_HIGH': 'investigate_handling',
    'ACTION_BUDGET_EXHAUSTED': 'review_limits',
    'SMS_BUDGET_EXHAUSTED': 'review_limits',
    'DELIVERY_CALLBACK_GAP': 'investigate_attempt',
    'SEND_OUTCOME_UNKNOWN': 'reconcile_unknown',
  };
  static const responseLabels = <String, String>{
    'investigate_backlog':
        'Investigate the retained business events and deferrals.',
    'investigate_handling':
        'Investigate the durable event and handling evidence.',
    'review_limits': 'Review current budget limits and recorded reservations.',
    'investigate_attempt':
        'Investigate the arm plan and authenticated callback observations.',
    'reconcile_unknown':
        'Reconcile the original attempt and callback evidence before another send.',
  };
  static const requiredEvidenceLimitCodes = <String>{
    'durable_handling_not_delivery',
    'framework_callbacks_not_carrier_proof',
    'callback_coverage_not_delivery_success',
    'budget_caps_not_measured_capacity',
    'costs_unmeasured',
    'configured_scope_only',
  };
  static const unavailableLimitCodes = <String>{
    'no_configured_scope',
    'measurement_timeout',
    'measurement_unavailable',
    'policy_changed',
  };

  static Map<String, int?> _metrics(
    Object? raw,
    Set<String> keys, {
    Set<String> nullable = const {},
  }) {
    final d = _object(raw, keys);
    return Map.unmodifiable({
      for (final key in keys)
        key: d[key] == null && nullable.contains(key) ? null : _count(d[key]),
    });
  }

  factory AdminReceiptOperationalTelemetry.parse(Object? raw) {
    final d = _object(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'window_start',
      'window_end',
      'window_seconds',
      'policy_revision',
      'mode',
      'emergency_stop',
      'configured_collection_count',
      'backlog',
      'handling',
      'budgets',
      'callbacks',
      'unknown',
      'alerts',
      'evidence_limit_codes',
      'financial_action',
      'send_action',
    });
    if (d['contract_version'] is! int ||
        d['contract_version'] != 1 ||
        d['scope'] != 'receipt_operations_configured_collections' ||
        d['window_seconds'] is! int ||
        d['window_seconds'] != 86400 ||
        !{
          'Shadow',
          'Dry-run',
          'Live-limited',
          'Live',
          'Paused',
        }.contains(d['mode']) ||
        d['emergency_stop'] is! bool ||
        d['mode'] == 'Paused' && d['emergency_stop'] != true ||
        d['financial_action'] != false ||
        d['send_action'] != false) {
      _invalid();
    }
    final checked = _instant(d['checked_at']),
        until = _instant(d['sample_valid_until']),
        start = _instant(d['window_start']),
        end = _instant(d['window_end']);
    if (end != checked ||
        until.difference(checked) != const Duration(seconds: 60) ||
        end.difference(start) != const Duration(seconds: 86400)) {
      _invalid();
    }
    final policyRevision = _count(
          d['policy_revision'],
          minimum: 1,
          maximum: 1000000000,
        ),
        collections = _count(d['configured_collection_count']);
    final rawLimits = d['evidence_limit_codes'];
    if (rawLimits is! List || rawLimits.any((code) => code is! String)) {
      _invalid();
    }
    final limits = rawLimits.cast<String>().toSet();
    if (limits.length != rawLimits.length ||
        !limits.containsAll(requiredEvidenceLimitCodes) ||
        !{
          ...requiredEvidenceLimitCodes,
          ...unavailableLimitCodes,
        }.containsAll(limits) ||
        (collections == 0) != limits.contains('no_configured_scope')) {
      _invalid();
    }
    final unavailable = limits.any(unavailableLimitCodes.contains);
    const sectionKeys = [
      'backlog',
      'handling',
      'budgets',
      'callbacks',
      'unknown',
    ];
    if (sectionKeys.any((key) => (d[key] == null) != unavailable)) _invalid();
    Map<String, int?>? backlog, handling;
    Map<String, dynamic>? budgets;
    Map<String, int>? callbacks, unknown;
    if (!unavailable) {
      backlog = _metrics(
        d['backlog'],
        {
          'unhandled_events',
          'oldest_unhandled_age_seconds',
          'due_deferrals',
          'source_busy_deferrals',
        },
        nullable: {'oldest_unhandled_age_seconds'},
      );
      final pending = backlog['unhandled_events']!;
      if ((pending == 0) != (backlog['oldest_unhandled_age_seconds'] == null) ||
          backlog['due_deferrals']! > pending ||
          backlog['source_busy_deferrals']! > pending) {
        _invalid();
      }
      handling = _metrics(
        d['handling'],
        {
          'events_created_24h',
          'events_handled_24h',
          'latency_p50_ms',
          'latency_p95_ms',
          'latency_max_ms',
        },
        nullable: {'latency_p50_ms', 'latency_p95_ms', 'latency_max_ms'},
      );
      final noHandled = handling['events_handled_24h'] == 0;
      for (final key in [
        'latency_p50_ms',
        'latency_p95_ms',
        'latency_max_ms',
      ]) {
        if ((handling[key] == null) != noHandled) _invalid();
      }
      if (!noHandled &&
          (handling['latency_p50_ms']! > handling['latency_p95_ms']! ||
              handling['latency_p95_ms']! > handling['latency_max_ms']!)) {
        _invalid();
      }
      final b = _object(d['budgets'], {
        'scope',
        'utc_day_start',
        'actions_reserved',
        'actions_cap',
        'sms_segments_reserved',
        'sms_segments_cap',
      });
      final day = _instant(b['utc_day_start']);
      if (b['scope'] != 'global_utc_day' ||
          day != DateTime.utc(end.year, end.month, end.day)) {
        _invalid();
      }
      budgets = Map.unmodifiable({
        'scope': 'global_utc_day',
        'utc_day_start': day,
        for (final key in [
          'actions_reserved',
          'actions_cap',
          'sms_segments_reserved',
          'sms_segments_cap',
        ])
          key: _count(b[key]),
      });
      callbacks = Map.unmodifiable(
        _metrics(d['callbacks'], {
          'armed_attempts_24h',
          'expected_segments',
          'covered_sent_segments',
          'covered_delivery_segments',
          'complete_delivery_callback_attempts',
          'conflicting_attempts',
        }).map((key, value) => MapEntry(key, value!)),
      );
      final armed = callbacks['armed_attempts_24h']!,
          segments = callbacks['expected_segments']!;
      if (segments < armed ||
          segments > armed * 10 ||
          callbacks['covered_sent_segments']! > segments ||
          callbacks['covered_delivery_segments']! > segments ||
          callbacks['complete_delivery_callback_attempts']! > armed ||
          callbacks['complete_delivery_callback_attempts']! >
              callbacks['covered_delivery_segments']! ||
          callbacks['conflicting_attempts']! > armed) {
        _invalid();
      }
      unknown = Map.unmodifiable(
        _metrics(d['unknown'], {
          'uncertain_attempts',
          'started_without_all_sent_callbacks',
          'observed_sent_without_all_delivery_callbacks',
          'callback_conflict_attempts',
        }).map((key, value) => MapEntry(key, value!)),
      );
    }
    final rawAlerts = d['alerts'];
    if (rawAlerts is! List || rawAlerts.length > ruleLabels.length) _invalid();
    final alerts = rawAlerts
        .map((item) => AdminReceiptTelemetryAlert.parse(item, checked))
        .toList();
    if (alerts.map((a) => a.id).toSet().length != alerts.length ||
        alerts.map((a) => a.ruleCode).toSet().length != alerts.length) {
      _invalid();
    }
    for (var index = 1; index < alerts.length; index++) {
      if (alerts[index - 1].ruleCode.compareTo(alerts[index].ruleCode) >= 0) {
        _invalid();
      }
    }
    return AdminReceiptOperationalTelemetry._(
      checkedAt: checked,
      validUntil: until,
      windowStart: start,
      windowEnd: end,
      policyRevision: policyRevision,
      mode: d['mode'] as String,
      emergencyStop: d['emergency_stop'] as bool,
      configuredCollectionCount: collections,
      backlog: backlog,
      handling: handling,
      budgets: budgets,
      callbacks: callbacks,
      unknown: unknown,
      alerts: List.unmodifiable(alerts),
      evidenceLimitCodes: Set.unmodifiable(limits),
    );
  }
}
