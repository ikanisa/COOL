import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_telemetry.dart';
import 'package:collect_app/core/data/exact_json_values.dart';

Never aggregateV3Invalid() => throw const FormatException(
  'Receipt aggregate v3 evidence could not be validated.',
);
Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((k) => k is! String || !keys.contains(k))) {
    aggregateV3Invalid();
  }
  return Map<String, dynamic>.from(value);
}

int _count(Object? value, [int min = 0, int max = 1000000000]) {
  if (value is! int) {
    aggregateV3Invalid();
  }
  return exactJsonInteger(
    value,
    field: 'aggregate v3 count',
    minimum: min,
    maximum: max,
  );
}

void _false(Map<String, dynamic> value, Iterable<String> keys) {
  if (keys.any((k) => value[k] != false)) aggregateV3Invalid();
}

/// A distinct v3 measurement for three authenticated Android protocols.
/// A v1 `not_admitted` status describes only the retained v1 aggregate.
/// This contract grants no financial, retry, dispatch or carrier authority.
class AdminReceiptAggregateV3 {
  const AdminReceiptAggregateV3._(
    this.status,
    this.reasonCode,
    this.probes,
    this.metrics,
  );
  final String status;
  final String? reasonCode;
  final Map<String, int> probes;
  final AdminReceiptOperationalTelemetry metrics;
  bool get admitted => status == 'admitted';
  int? get configuredCollectionCount => probes['collections'];
  bool isFresh(DateTime now) => metrics.isFresh(now);
  static const reasons = {
    'telemetry_disabled',
    'admission_disabled',
    'no_configured_scope',
    'collection_ceiling',
    'configured_scope_invalid',
    'projection_seed_incomplete',
    'projection_dirty',
    'pending_ceiling',
    'created_ceiling',
    'handled_ceiling',
    'reservation_ceiling',
    'primary_recent_ceiling',
    'successor_recent_ceiling',
    'primary_unresolved_ceiling',
    'successor_unresolved_ceiling',
    'notice_recent_ceiling',
    'notice_unresolved_ceiling',
    'measurement_invalid',
    'measurement_timeout',
    'measurement_unavailable',
    'source_binding_unavailable',
  };
  static const ceilings = {
    'collections': 8,
    'pending': 128,
    'created': 128,
    'global_handled': 128,
    'global_reservations': 128,
    'recent_primary': 32,
    'recent_successor': 32,
    'unresolved_primary': 32,
    'unresolved_successor': 32,
    'recent_notice': 32,
    'unresolved_notice': 32,
  };
  factory AdminReceiptAggregateV3.parse(Object? raw) {
    final d = _object(raw, {
      'contract_version',
      'scope',
      'status',
      'reason_code',
      'policy_revision',
      'mode',
      'emergency_stop',
      'checked_at',
      'sample_valid_until',
      'window_start',
      'window_end',
      'window_seconds',
      'protocol_families',
      'backlog',
      'handling',
      'budgets',
      'callbacks',
      'unknown',
      'probe_counts',
      'financial_action',
      'send_action',
      'carrier_proof',
      'delivery_proven',
      'evidence_limit_codes',
    });
    if (d['contract_version'] is! int ||
        d['contract_version'] != 3 ||
        d['scope'] != 'configured_receipt_operations_three_protocols' ||
        !{'admitted', 'not_admitted'}.contains(d['status'])) {
      aggregateV3Invalid();
    }
    _false(d, [
      'financial_action',
      'send_action',
      'carrier_proof',
      'delivery_proven',
    ]);
    final families = d['protocol_families'];
    if (families is! List ||
        families.length != 3 ||
        families[0] != 'primary_v2' ||
        families[1] != 'receipt_successor_v1' ||
        families[2] != 'receipt_notice_v1') {
      aggregateV3Invalid();
    }
    final admitted = d['status'] == 'admitted';
    if (admitted
        ? d['reason_code'] != null
        : !reasons.contains(d['reason_code'])) {
      aggregateV3Invalid();
    }
    final rawProbes = d['probe_counts'];
    if (rawProbes is! Map) aggregateV3Invalid();
    final probes = rawProbes.isEmpty && !admitted
        ? <String, int>{}
        : _object(
            rawProbes,
            ceilings.keys.toSet(),
          ).map((k, v) => MapEntry(k, _count(v)));
    if (admitted &&
        (probes['collections'] == 0 ||
            ceilings.entries.any((e) => probes[e.key]! > e.value))) {
      aggregateV3Invalid();
    }
    final limits = d['evidence_limit_codes'];
    const required =
        AdminReceiptOperationalTelemetry.requiredEvidenceLimitCodes;
    if (limits is! List ||
        limits.length != required.length ||
        limits.any((v) => !required.contains(v)) ||
        limits.toSet().length != required.length) {
      aggregateV3Invalid();
    }
    const sections = ['backlog', 'handling', 'budgets', 'callbacks', 'unknown'];
    if (sections.any((k) => (d[k] != null) != admitted)) aggregateV3Invalid();
    // Reuse the existing metric cross-field validator after validating the
    // closed v3 wire. This private value is never accepted as a v1 or v2 RPC result.
    final count = probes['collections'] ?? 0;
    final validated = AdminReceiptOperationalTelemetry.parse({
      for (final k in [
        'checked_at',
        'sample_valid_until',
        'window_start',
        'window_end',
        'window_seconds',
        'policy_revision',
        'mode',
        'emergency_stop',
        ...sections,
        'financial_action',
        'send_action',
      ])
        k: d[k],
      'contract_version': 1,
      'scope': 'receipt_operations_configured_collections',
      'configured_collection_count': count,
      'alerts': <Object?>[],
      'evidence_limit_codes': [
        ...required,
        if (count == 0) 'no_configured_scope',
        if (!admitted && count != 0) 'measurement_unavailable',
      ],
    });
    if (admitted) {
      for (final k in sections) {
        for (final value in (d[k] as Map).values) {
          if (value is num) _count(value);
        }
      }
      final backlog = validated.backlog!, handling = validated.handling!;
      final callbacks = validated.callbacks!, unknown = validated.unknown!;
      if (backlog['unhandled_events'] != probes['pending'] ||
          handling['events_created_24h'] != probes['created'] ||
          handling['events_handled_24h']! > probes['global_handled']! ||
          callbacks['armed_attempts_24h']! >
              probes['recent_primary']! +
                  probes['recent_successor']! +
                  probes['recent_notice']! ||
          unknown.values.any((v) => v > 192) ||
          callbacks['armed_attempts_24h']! > 96 ||
          callbacks['expected_segments']! > 960) {
        aggregateV3Invalid();
      }
    }
    return AdminReceiptAggregateV3._(
      d['status'] as String,
      d['reason_code'] as String?,
      Map.unmodifiable(probes),
      validated,
    );
  }
}

/// Immutable side evidence tied to the original worker request, not a live
/// health result. Expired history stays readable; freshness is checked separately.
class AdminReceiptAggregateSampleV3 {
  const AdminReceiptAggregateSampleV3._(
    this.requestId,
    this.measurement,
    this.recordedAt,
    this.expiresAt,
    this.configurationRevision,
    this.telemetryRevision,
    this.policyRevision,
  );
  final String requestId;
  final AdminReceiptAggregateV3? measurement;
  final DateTime? recordedAt, expiresAt;
  final int? configurationRevision, telemetryRevision, policyRevision;
  bool get available => measurement != null;
  bool current(DateTime now) =>
      measurement != null &&
      measurement!.isFresh(now) &&
      !now.toUtc().isBefore(recordedAt!) &&
      now.toUtc().isBefore(expiresAt!);
  factory AdminReceiptAggregateSampleV3.parse(Object? raw, String requestId) {
    cancelUuid(requestId);
    final d = _object(raw, {
      'contract_version',
      'request_id',
      'status',
      'result',
      'financial_action',
      'send_action',
    });
    if (d['contract_version'] is! int ||
        d['contract_version'] != 3 ||
        d['request_id'] != requestId ||
        !{'available', 'unavailable'}.contains(d['status'])) {
      aggregateV3Invalid();
    }
    _false(d, ['financial_action', 'send_action']);
    if (d['status'] == 'unavailable') {
      if (d['result'] != null) aggregateV3Invalid();
      return AdminReceiptAggregateSampleV3._(
        requestId,
        null,
        null,
        null,
        null,
        null,
        null,
      );
    }
    final r = _object(d['result'], {
      'contract_version',
      'request_id',
      'configuration_revision',
      'telemetry_revision',
      'policy_revision',
      'expires_at',
      'recorded_at',
      'projection',
      'measurement',
      'financial_action',
      'send_action',
    });
    if (r['contract_version'] is! int ||
        r['contract_version'] != 3 ||
        r['request_id'] != requestId) {
      aggregateV3Invalid();
    }
    _false(r, ['financial_action', 'send_action']);
    for (final k in [
      'configuration_revision',
      'telemetry_revision',
      'policy_revision',
    ]) {
      _count(r[k], 1);
    }
    final at = cancelInstant(r['recorded_at']),
        expiry = cancelInstant(r['expires_at']);
    final measurement = AdminReceiptAggregateV3.parse(r['measurement']);
    if (measurement.metrics.checkedAt.isAfter(at) ||
        at.isAfter(expiry) ||
        measurement.metrics.policyRevision != r['policy_revision']) {
      aggregateV3Invalid();
    }
    if (r['projection'] != null) {
      final p = _object(r['projection'], {
        'processed',
        'busy',
        'unavailable',
        'complete',
      });
      final processed = _count(p['processed'], 0, 25),
          busy = _count(p['busy'], 0, 25),
          unavailable = _count(p['unavailable'], 0, 25);
      if (processed + busy + unavailable > 25 ||
          p['complete'] is! bool ||
          measurement.admitted && p['complete'] != true ||
          p['complete'] == true && busy + unavailable != 0) {
        aggregateV3Invalid();
      }
    } else if (measurement.admitted) {
      aggregateV3Invalid();
    }
    return AdminReceiptAggregateSampleV3._(
      requestId,
      measurement,
      at,
      expiry,
      r['configuration_revision'] as int,
      r['telemetry_revision'] as int,
      r['policy_revision'] as int,
    );
  }
}
