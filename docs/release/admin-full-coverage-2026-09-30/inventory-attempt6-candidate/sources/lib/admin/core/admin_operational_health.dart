import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

/// Version1 of the redacted148 health contract. Arbitrary diagnostic strings
/// and malformed/missing measurements never become apparent healthy values.
class AdminOperationalHealth {
  AdminOperationalHealth._(
    this.checkedAt,
    this.validUntil,
    this.status,
    this.schedulerState,
    this.metrics,
    this.alerts,
  );

  final DateTime checkedAt, validUntil;
  final String status, schedulerState;
  final Map<String, int?> metrics;
  final Map<String, String> alerts;

  static const metricLabels = <String, String>{
    'durable_receipts_24h': 'Durable receipts in 24 hours',
    'sms_pending': 'Receipts awaiting parsing',
    'sms_pending_age_seconds': 'Oldest receipt awaiting parsing',
    'sms_failed_24h': 'Failed parses in 24 hours',
    'sms_parsed_24h': 'Parsed receipts in 24 hours',
    'sms_expired_parse_leases': 'Expired parsing leases',
    'unallocated_events': 'Unmatched payment events',
    'payments_review': 'Payments awaiting review',
    'payment_review_age_seconds': 'Oldest payment awaiting review',
    'payments_posted_24h': 'Posted payments in 24 hours',
    'reconciliation_open': 'Open reconciliation exceptions',
    'reversals_24h': 'Reversals in 24 hours',
    'finality_processing': 'Finality requests processing',
    'finality_processed_24h': 'Finality requests processed in 24 hours',
    'push_queued': 'Notifications queued',
    'push_due': 'Notifications due',
    'push_due_age_seconds': 'Oldest notification due',
    'push_processing': 'Notifications processing',
    'push_expired_leases': 'Expired notification leases',
    'push_missing_leases': 'Missing notification leases',
    'push_failed': 'Failed notification deliveries',
    'push_attempts_24h': 'Notification attempts in 24 hours',
    'push_failed_24h': 'Failed notification attempts in 24 hours',
    'push_provider_accepts_24h': 'Provider acceptances in 24 hours',
    'push_retry_24h': 'Notification retries in 24 hours',
    'push_latency_p95_ms': 'Notification attempt latency, 95th percentile',
    'receipt_ack_generated_24h':
        'Receipt acknowledgments generated in 24 hours',
    'receipt_rejected_24h': 'Receipt requests rejected in 24 hours',
    'receipt_telemetry_age_seconds': 'Receipt telemetry age',
    'receipt_ack_latency_mean_ms': 'Mean receipt acknowledgment latency',
    'push_scheduler_age_seconds': 'Last successful notification scheduler run',
  };
  static const evidenceLimits = [
    'ACK generation does not prove device receipt.',
    'Provider acceptance does not prove user delivery.',
    'Scheduler activation does not prove provider configuration.',
  ];
  static const rules = <String, (String, int, String?, String)>{
    'receipt_parse_backlog': (
      'sms_pending',
      100,
      null,
      'Receipt parsing backlog',
    ),
    'receipt_parse_age': (
      'sms_pending_age_seconds',
      300,
      'sms_pending',
      'Receipt parsing age',
    ),
    'receipt_parse_failure': (
      'sms_failed_24h',
      1,
      null,
      'Receipt parsing failures',
    ),
    'receipt_parser_lease_expired': (
      'sms_expired_parse_leases',
      1,
      null,
      'Receipt parsing leases',
    ),
    'payment_unmatched': ('unallocated_events', 1, null, 'Unmatched payments'),
    'payment_review_age': (
      'payment_review_age_seconds',
      3600,
      'payments_review',
      'Payment review age',
    ),
    'reconciliation_exception': (
      'reconciliation_open',
      1,
      null,
      'Reconciliation exceptions',
    ),
    'push_queue_age': (
      'push_due_age_seconds',
      120,
      'push_due',
      'Notification queue age',
    ),
    'push_expired_lease': (
      'push_expired_leases',
      1,
      null,
      'Expired notification leases',
    ),
    'push_missing_lease': (
      'push_missing_leases',
      1,
      null,
      'Missing notification leases',
    ),
    'push_attempt_failure': (
      'push_failed_24h',
      5,
      null,
      'Notification attempt failures',
    ),
    'receipt_telemetry_stale': (
      'receipt_telemetry_age_seconds',
      300,
      'durable_receipts_24h',
      'Receipt telemetry freshness',
    ),
    'push_scheduler_stale': (
      'push_scheduler_age_seconds',
      180,
      'push_due',
      'Notification scheduler freshness',
    ),
  };

  static Never _invalid() => throw const FormatException(
    'Health sample could not be validated. Refresh to check again.',
  );

  static Map<String, dynamic> _object(Object? raw, Set<String> keys) {
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((key) => key is! String || !keys.contains(key))) {
      _invalid();
    }
    return Map<String, dynamic>.from(raw);
  }

  static DateTime _instant(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
        ).hasMatch(value)) {
      _invalid();
    }
    final date = DateTime.tryParse(value);
    if (date == null ||
        date.toUtc().toIso8601String().substring(0, 19) !=
            value.substring(0, 19)) {
      _invalid();
    }
    return date.toUtc();
  }

  factory AdminOperationalHealth.parse(Object? raw) {
    final d = _object(raw, {
      'id',
      'contract_version',
      'database',
      'auth',
      'parser_pending_sms',
      'failed_sms_parse',
      'unallocated_events',
      'queued_notifications',
      'processing_notifications',
      'failed_notifications',
      'checked_at',
      'metrics',
      'alerts',
      'health_status',
      'sample_valid_until',
      'window_seconds',
      'threshold_version',
      'scheduler',
      'evidence_limits',
    });
    if (d['id'] != 'system' ||
        d['contract_version'] is! int ||
        d['contract_version'] != 1 ||
        d['database'] != 'reachable' ||
        d['auth'] != 'authenticated' ||
        d['window_seconds'] is! int ||
        d['window_seconds'] != 86400 ||
        d['threshold_version'] is! int ||
        d['threshold_version'] != 1) {
      _invalid();
    }
    final checked = _instant(d['checked_at']),
        expires = _instant(d['sample_valid_until']);
    if (expires.difference(checked) != const Duration(seconds: 60)) _invalid();
    final input = _object(d['metrics'], metricLabels.keys.toSet());
    final metrics = <String, int?>{};
    for (final entry in input.entries) {
      final nullable =
          entry.key.endsWith('_seconds') || entry.key.endsWith('_ms');
      final value = entry.value;
      if (!(nullable && value == null) &&
          (value is! int || value < 0 || value > 9007199254740991)) {
        _invalid();
      }
      metrics[entry.key] = value as int?;
    }
    for (final alias in const {
      'parser_pending_sms': 'sms_pending',
      'failed_sms_parse': 'sms_failed_24h',
      'unallocated_events': 'unallocated_events',
      'queued_notifications': 'push_queued',
      'processing_notifications': 'push_processing',
      'failed_notifications': 'push_failed',
    }.entries) {
      if (d[alias.key] is! int || d[alias.key] != metrics[alias.value]) {
        _invalid();
      }
    }
    final scheduler = _object(d['scheduler'], {
      'state',
      'configuration_verified',
    });
    if (!{'enabled', 'disabled', 'unknown'}.contains(scheduler['state']) ||
        scheduler['configuration_verified'] != false) {
      _invalid();
    }
    final limits = d['evidence_limits'];
    if (limits is! List ||
        limits.length != evidenceLimits.length ||
        List.generate(
          limits.length,
          (i) => limits[i] == evidenceLimits[i],
        ).any((v) => !v)) {
      _invalid();
    }
    final values = d['alerts'];
    if (values is! List || values.length != rules.length) _invalid();
    final alerts = <String, String>{};
    for (final value in values) {
      final a = _object(value, {'code', 'metric', 'threshold', 'state'});
      final rule = rules[a['code']];
      if (rule == null ||
          alerts.containsKey(a['code']) ||
          a['metric'] != rule.$1 ||
          a['threshold'] is! int ||
          a['threshold'] != rule.$2) {
        _invalid();
      }
      final metric = metrics[rule.$1];
      final expected = rule.$3 != null && metrics[rule.$3] == 0
          ? 'not_applicable'
          : metric == null
          ? 'unknown'
          : metric >= rule.$2
          ? 'attention'
          : 'ok';
      if (a['state'] != expected) _invalid();
      alerts[a['code'] as String] = expected;
    }
    final status = alerts.values.contains('attention')
        ? 'attention'
        : alerts.values.contains('unknown')
        ? 'unknown'
        : 'ok';
    if (d['health_status'] != status) _invalid();
    return AdminOperationalHealth._(
      checked,
      expires,
      status,
      scheduler['state'] as String,
      Map.unmodifiable(metrics),
      Map.unmodifiable(alerts),
    );
  }

  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);
}

class AdminOperationalHealthPanel extends StatefulWidget {
  const AdminOperationalHealthPanel({
    required this.data,
    required this.onRefresh,
    this.clock = DateTime.now,
    super.key,
  });
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;
  final DateTime Function() clock;
  @override
  State<AdminOperationalHealthPanel> createState() =>
      _AdminOperationalHealthPanelState();
}

class _AdminOperationalHealthPanelState
    extends State<AdminOperationalHealthPanel> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AdminOperationalHealth health;
    try {
      health = AdminOperationalHealth.parse(widget.data);
    } catch (_) {
      return CollectCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Health unavailable'),
            const Text(
              'Health sample could not be validated. Refresh to check again.',
            ),
            CollectButton(label: 'Refresh health', onPressed: widget.onRefresh),
          ],
        ),
      );
    }
    final fresh = health.isFresh(widget.clock());
    final status = !fresh
        ? 'Sample expired or clock unavailable'
        : switch (health.status) {
            'attention' => 'Attention required',
            'unknown' => 'Measurements unavailable',
            _ => 'No threshold exceeded',
          };
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Receipt, payment and notification health',
          ),
          Semantics(
            liveRegion: true,
            child: InfoSecurityBanner(
              title: status,
              message: fresh
                  ? 'These checks describe the current operational sample.'
                  : 'Refresh for current measurements. Previous values are hidden.',
              tone: !fresh || health.status == 'attention'
                  ? CollectStatusTone.warning
                  : CollectStatusTone.info,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Checked ${health.checkedAt.toIso8601String()} · 24-hour activity window',
          ),
          Text(
            fresh
                ? 'Notification schedule at sample: ${health.schedulerState}. Provider configuration unverified.'
                : 'Notification schedule not verified for the current time.',
          ),
          const SizedBox(height: 12),
          for (final limit in AdminOperationalHealth.evidenceLimits)
            Text(limit),
          const SizedBox(height: 12),
          CollectButton(label: 'Refresh health', onPressed: widget.onRefresh),
          if (!fresh)
            const Text(
              'Refresh for current measurements. Previous values are hidden.',
            ),
          if (fresh) ...[
            const SectionHeader(title: 'Alert checks'),
            for (final alert in health.alerts.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${AdminOperationalHealth.rules[alert.key]!.$4}: ${switch (alert.value) {
                    'attention' => 'Attention required',
                    'unknown' => 'Not measured',
                    'not_applicable' => 'No queued work',
                    _ => 'Below threshold',
                  }}',
                ),
              ),
            const SectionHeader(title: 'Measurements'),
            for (final metric in health.metrics.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${AdminOperationalHealth.metricLabels[metric.key]}: ${metric.value == null ? 'Not measured' : '${metric.value}${metric.key.endsWith('_ms')
                            ? ' ms'
                            : metric.key.endsWith('_seconds')
                            ? ' seconds'
                            : ''}'}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
