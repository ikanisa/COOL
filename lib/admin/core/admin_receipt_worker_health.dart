import 'admin_exception_models.dart';

/// Redacted v1 health from the trusted exception worker. Reservations count
/// whole scheduled batches; they never establish processing or SMS delivery.
class AdminReceiptWorkerHealth {
  const AdminReceiptWorkerHealth._({
    required this.checkedAt,
    required this.validUntil,
    required this.revision,
    required this.enabled,
    required this.state,
    required this.requestId,
    required this.createdAt,
    required this.expiresAt,
    required this.recordedAt,
    required this.outcome,
    required this.pendingSources,
    required this.transportConfigured,
    required this.alerts,
    required this.budgets,
  });

  final DateTime checkedAt, validUntil;
  final int revision, pendingSources;
  final bool enabled, transportConfigured;
  final String state;
  final String? requestId, outcome;
  final DateTime? createdAt, expiresAt, recordedAt;
  final List<String> alerts;
  final Map<String, ({int reserved, int cap})> budgets;

  static const states = <String, String>{
    'inactive': 'Exception worker paused',
    'unobserved': 'No scheduled job observed',
    'observed': 'Latest job has recorded evidence',
    'pending': 'Latest job is awaiting evidence',
    'unknown': 'Latest job outcome is unknown',
    'expired_without_receipt': 'Latest job expired without a worker receipt',
  };
  static const alertLabels = <String, String>{
    'WORKER_STALE': 'Worker evidence is overdue',
    'ORIGINAL_OUTCOME_UNKNOWN': 'Original job outcome needs reconciliation',
    'ORIGINAL_EXPIRED_UNHANDLED':
        'Expired original job has no recorded worker receipt',
    'DEFERRAL_BACKLOG': 'Receipt deferral backlog needs investigation',
    'SOURCE_REFUSALS': 'Some receipt sources were refused',
    'TRANSPORT_UNCONFIGURED': 'Worker transport is unconfigured',
    'WORKER_QUOTA_EXHAUSTED': 'Worker scheduling budget is exhausted',
  };
  static const budgetLabels = <String, String>{
    'jobs': 'Scheduled jobs',
    'scan_sources': 'Source scans',
    'escalations': 'Inbox escalations',
  };

  String get stateLabel => states[state]!;
  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);

  factory AdminReceiptWorkerHealth.parse(Object? raw) {
    final data = exceptionObject(raw, {
      'contract_version',
      'checked_at',
      'sample_valid_until',
      'configuration_revision',
      'enabled',
      'state',
      'last_request_id',
      'last_created_at',
      'last_expires_at',
      'last_recorded_at',
      'last_outcome',
      'pending_sources',
      'alerts',
      'transport_configured',
      'day_jobs_reserved',
      'day_scan_sources_reserved',
      'day_escalations_reserved',
      'day_jobs_cap',
      'day_scan_sources_cap',
      'day_escalations_cap',
      'source_scan_complete',
      'financial_action',
      'send_action',
      'external_send',
    });
    int integer(String name, int minimum, int maximum) {
      final value = data[name];
      if (value is! int || value < minimum || value > maximum) {
        exceptionInvalid();
      }
      return value;
    }

    DateTime? instant(String name) =>
        data[name] == null ? null : exceptionInstant(data[name]);
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    final state = data['state'];
    final enabled = data['enabled'];
    final configured = data['transport_configured'];
    final request = data['last_request_id'] == null
        ? null
        : exceptionUuid(data['last_request_id']);
    final created = instant('last_created_at');
    final expires = instant('last_expires_at');
    final recorded = instant('last_recorded_at');
    final outcome = data['last_outcome'];
    final alerts = data['alerts'];
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        until.difference(checked) != const Duration(seconds: 60) ||
        enabled is! bool ||
        configured is! bool ||
        state is! String ||
        !states.containsKey(state) ||
        (!enabled) != (state == 'inactive') ||
        (request == null) != (created == null) ||
        (request == null) != (expires == null) ||
        (recorded == null) != (outcome == null) ||
        outcome != null && !{'completed', 'busy'}.contains(outcome) ||
        state == 'unobserved' && request != null ||
        !{'inactive', 'unobserved'}.contains(state) && request == null ||
        state == 'observed' && recorded == null ||
        data['source_scan_complete'] != false ||
        data['financial_action'] != false ||
        data['send_action'] != false ||
        data['external_send'] != false ||
        alerts is! List ||
        alerts.length > alertLabels.length ||
        alerts.any(
          (value) => value is! String || !alertLabels.containsKey(value),
        ) ||
        alerts.toSet().length != alerts.length) {
      exceptionInvalid();
    }
    if (created != null &&
        expires != null &&
        (expires.difference(created) != const Duration(seconds: 90) ||
            created.isAfter(checked.add(const Duration(seconds: 5))) ||
            state == 'pending' && !expires.isAfter(checked) ||
            {'unknown', 'expired_without_receipt'}.contains(state) &&
                expires.isAfter(checked))) {
      exceptionInvalid();
    }
    if (recorded?.isAfter(checked.add(const Duration(seconds: 5))) == true ||
        alerts.contains('ORIGINAL_OUTCOME_UNKNOWN') != (state == 'unknown') ||
        alerts.contains('ORIGINAL_EXPIRED_UNHANDLED') !=
            (state == 'expired_without_receipt') ||
        alerts.contains('TRANSPORT_UNCONFIGURED') != (enabled && !configured) ||
        alerts.contains('WORKER_STALE') !=
            (enabled &&
                (recorded == null ||
                    recorded.isBefore(
                      checked.subtract(const Duration(seconds: 180)),
                    )))) {
      exceptionInvalid();
    }
    final budgets = <String, ({int reserved, int cap})>{};
    for (final entry in {
      'jobs': 1440,
      'scan_sources': 36000,
      'escalations': 28800,
    }.entries) {
      // A lowered current cap may be below retained reservations. Do not clamp
      // or reject this legitimate, actionable over-budget state.
      budgets[entry.key] = (
        reserved: integer('day_${entry.key}_reserved', 0, 1000000000),
        cap: integer('day_${entry.key}_cap', 1, entry.value),
      );
    }
    return AdminReceiptWorkerHealth._(
      checkedAt: checked,
      validUntil: until,
      revision: integer('configuration_revision', 1, 1000000000),
      enabled: enabled,
      state: state,
      requestId: request,
      createdAt: created,
      expiresAt: expires,
      recordedAt: recorded,
      outcome: outcome as String?,
      pendingSources: integer('pending_sources', 0, 1000000000),
      transportConfigured: configured,
      alerts: List.unmodifiable(alerts.cast<String>()),
      budgets: Map.unmodifiable(budgets),
    );
  }
}
