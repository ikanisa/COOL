import '../../core/data/exact_json_values.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_successor_models.dart';

Never executionInvalid() => throw const FormatException(
  'Receipt execution evidence could not be validated.',
);
Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, dynamic>.unmodifiable(
    value.map((key, value) => MapEntry(key as String, _freeze(value))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
Map<String, dynamic> _object(Object? raw, Set<String> keys) =>
    successorObject(raw, keys);
const _limits = {
  'financial_action',
  'send_action',
  'carrier_proof',
  'delivery_proven',
};
void _contract(Map<String, dynamic> r, String scope) {
  if (r['contract_version'] is! int ||
      r['contract_version'] != 4 ||
      r['scope'] != scope ||
      _limits.any((key) => r[key] != false)) {
    executionInvalid();
  }
}

void _sample(Map<String, dynamic> r) {
  if (cancelInstant(
        r['sample_valid_until'],
      ).difference(cancelInstant(r['checked_at'])) !=
      const Duration(seconds: 60)) {
    executionInvalid();
  }
}

const _observedStates = {'armed_unknown', 'observed_sent', 'uncertain'};
Map<String, dynamic> _route(Object? raw, String approval, String root) {
  final r = _object(raw, {
    'route_version',
    'route_kind',
    'primary_receipt_id',
    'dispatch_job_id',
    'approval_id',
  });
  if (r['route_version'] is! int ||
      r['route_version'] != 1 ||
      r['route_kind'] != 'receipt_successor' ||
      r['primary_receipt_id'] != cancelUuid(root) ||
      r['approval_id'] != cancelUuid(approval) ||
      cancelUuid(r['dispatch_job_id']) == root) {
    executionInvalid();
  }
  return r;
}

List<Object?> _array(Object? raw, int maximum) {
  if (raw is! List || raw.length > maximum) executionInvalid();
  return raw;
}

int _integer(Object? raw, int minimum, int maximum) => exactJsonInteger(
  raw,
  field: 'receipt execution integer',
  minimum: minimum,
  maximum: maximum,
);

class AdminReceiptSuccessorExecutionSnapshot {
  AdminReceiptSuccessorExecutionSnapshot._(this.row);
  final Map<String, dynamic> row;
  String get approvalId => row['approval_id'] as String;
  String? get primaryReceiptId => row['primary_receipt_id'] as String?;
  int? get cutoff => row['cutoff_revision'] as int?;
  bool get available => row['status'] == 'available';
  Map<String, dynamic>? get execution =>
      row['execution'] as Map<String, dynamic>?;
  String? get state => execution?['state'] as String?;
  String? get attemptId =>
      (execution?['attempt'] as Map?)?['attempt_id'] as String?;
  DateTime get checkedAt => cancelInstant(row['checked_at']);
  DateTime get validUntil => cancelInstant(row['sample_valid_until']);
  bool fresh(DateTime now) => successorFresh(checkedAt, validUntil, now);

  factory AdminReceiptSuccessorExecutionSnapshot.parse(
    Object? raw,
    String approval,
    String root,
  ) {
    cancelUuid(approval);
    cancelUuid(root);
    final r = _object(raw, {
      'contract_version',
      'scope',
      'approval_id',
      'checked_at',
      'sample_valid_until',
      'status',
      'primary_receipt_id',
      'cutoff_revision',
      'execution',
      ..._limits,
      'retained_primary',
    });
    _contract(r, 'rw_receipt_successor_execution');
    _sample(r);
    if (r['approval_id'] != approval || r['retained_primary'] != true) {
      executionInvalid();
    }
    if (r['status'] == 'unavailable') {
      if (r['primary_receipt_id'] != null ||
          r['cutoff_revision'] != null ||
          r['execution'] != null) {
        executionInvalid();
      }
    } else {
      if (r['status'] != 'available' || r['primary_receipt_id'] != root) {
        executionInvalid();
      }
      final cutoff = cancelRevision(r['cutoff_revision']);
      final e = _object(r['execution'], {
        'route',
        'state',
        'attempt',
        'arm',
        'revocation',
        'execution_events',
        'observation_count',
        'latest_projection',
        'archive',
      });
      if (e['observation_count'] != null) executionInvalid();
      final events = _array(e['execution_events'], 2);
      if (e['state'] == 'not_materialized') {
        if (events.isNotEmpty ||
            [
              'route',
              'attempt',
              'arm',
              'revocation',
              'latest_projection',
              'archive',
            ].any((key) => e[key] != null)) {
          executionInvalid();
        }
      } else {
        final route = _route(e['route'], approval, root);
        final a = _object(e['attempt'], {
          'attempt_id',
          'device_id',
          'run_id',
          'fence_version',
          'grant_request_id',
          'reservation_id',
          'segment_count',
          'body_sha256',
          'destination_sha256',
          'issued_at',
          'expires_at',
        });
        for (final key in [
          'attempt_id',
          'device_id',
          'run_id',
          'grant_request_id',
          'reservation_id',
        ]) {
          cancelUuid(a[key]);
        }
        cancelRevision(a['fence_version']);
        final segments = _integer(a['segment_count'], 1, 10);
        successorHash(a['body_sha256']);
        successorHash(a['destination_sha256']);
        final issued = cancelInstant(a['issued_at']),
            expiry = cancelInstant(a['expires_at']);
        final checked = cancelInstant(r['checked_at']);
        if (!expiry.isAfter(issued) ||
            expiry.difference(issued) > const Duration(seconds: 30) ||
            issued.isAfter(checked) ||
            events.isEmpty) {
          executionInvalid();
        }
        Map<String, dynamic>? previous;
        for (var i = 0; i < events.length; i++) {
          final event = _object(events[i], {
            'event_id',
            'event_kind',
            'request_id',
            'approved_event_id',
            'approval_request_id',
            'lineage_before',
            'lineage_after',
            'recorded_at',
          });
          for (final key in [
            'event_id',
            'request_id',
            'approved_event_id',
            'approval_request_id',
          ]) {
            cancelUuid(event[key]);
          }
          final before = cancelRevision(event['lineage_before']),
              after = cancelRevision(event['lineage_after']);
          if (after != before + 1 ||
              after > cutoff ||
              event['event_kind'] != (i == 0 ? 'grant' : 'arm') ||
              cancelInstant(event['recorded_at']).isAfter(checked) ||
              i == 0 && event['request_id'] != a['grant_request_id'] ||
              previous != null &&
                  (before != previous['lineage_after'] ||
                      event['approved_event_id'] !=
                          previous['approved_event_id'] ||
                      event['approval_request_id'] !=
                          previous['approval_request_id'])) {
            executionInvalid();
          }
          previous = event;
        }
        final armed = e['arm'] != null;
        if (armed) {
          final arm = _object(e['arm'], {
            'request_id',
            'reservation_sha256',
            'armed_at',
          });
          cancelUuid(arm['request_id']);
          successorHash(arm['reservation_sha256']);
          final time = cancelInstant(arm['armed_at']);
          if (events.length != 2 ||
              arm['request_id'] != previous!['request_id'] ||
              time.isBefore(issued) ||
              !time.isBefore(expiry) ||
              time.isAfter(checked) ||
              e['revocation'] != null ||
              !_observedStates.contains(e['state'])) {
            executionInvalid();
          }
          final latest = e['latest_projection'];
          if (latest != null) {
            final p = _object(latest, {
              'request_id',
              'lineage_revision',
              'recorded_at',
              'state',
            });
            cancelUuid(p['request_id']);
            final revision = cancelRevision(p['lineage_revision']);
            if (revision <= (previous['lineage_after'] as int) ||
                revision > cutoff ||
                p['state'] != e['state'] ||
                cancelInstant(p['recorded_at']).isBefore(time) ||
                cancelInstant(p['recorded_at']).isAfter(checked)) {
              executionInvalid();
            }
          } else if (e['state'] != 'armed_unknown') {
            executionInvalid();
          }
          if (e['archive'] != null) {
            final ack = _object(e['archive'], {
              'archive_ack_id',
              'request_id',
              'route',
              'callback_requests',
              'evidence_sha256',
              'recorded_at',
              'journal_ack',
              'send_authority',
              'carrier_proof',
              'delivery_proven',
            });
            cancelUuid(ack['archive_ack_id']);
            cancelUuid(ack['request_id']);
            successorHash(ack['evidence_sha256']);
            final other = _route(ack['route'], approval, root);
            if (other['dispatch_job_id'] != route['dispatch_job_id'] ||
                ack['journal_ack'] != true ||
                ack['send_authority'] != false ||
                ack['carrier_proof'] != false ||
                ack['delivery_proven'] != false ||
                latest == null ||
                e['state'] == 'armed_unknown' ||
                cancelInstant(ack['recorded_at']).isBefore(time) ||
                cancelInstant(ack['recorded_at']).isAfter(checked)) {
              executionInvalid();
            }
            final refs = _array(ack['callback_requests'], 20);
            final callbacks = <String>{}, requests = <String>{};
            if (refs.length != segments * 2) executionInvalid();
            for (final ref in refs) {
              final v = _object(ref, {
                'callback_id',
                'request_id',
                'request_sha256',
              });
              if (!callbacks.add(cancelUuid(v['callback_id'])) ||
                  !requests.add(cancelUuid(v['request_id']))) {
                executionInvalid();
              }
              successorHash(v['request_sha256']);
            }
          }
        } else {
          if (events.length != 1 ||
              e['latest_projection'] != null ||
              e['archive'] != null ||
              !{
                'unarmed_granted',
                'unarmed_expired',
                'unarmed_revoked',
              }.contains(e['state'])) {
            executionInvalid();
          }
          if (e['revocation'] != null) {
            final v = _object(e['revocation'], {
              'approval_event_id',
              'recorded_at',
            });
            cancelUuid(v['approval_event_id']);
            if (e['state'] != 'unarmed_revoked' ||
                cancelInstant(v['recorded_at']).isBefore(issued) ||
                cancelInstant(v['recorded_at']).isAfter(checked)) {
              executionInvalid();
            }
          } else if (e['state'] == 'unarmed_revoked' ||
              (e['state'] == 'unarmed_granted') != expiry.isAfter(checked)) {
            executionInvalid();
          }
        }
      }
    }
    return AdminReceiptSuccessorExecutionSnapshot._(
      _freeze(r) as Map<String, dynamic>,
    );
  }
}

class AdminReceiptSuccessorObservationPage {
  AdminReceiptSuccessorObservationPage._(this.row);
  final Map<String, dynamic> row;
  List<Map<String, dynamic>> get items =>
      (row['items'] as List).cast<Map<String, dynamic>>();
  int? get next => row['next_after_revision'] as int?;
  bool get available => row['status'] == 'available';
  DateTime get checkedAt => cancelInstant(row['checked_at']);
  DateTime get validUntil => cancelInstant(row['sample_valid_until']);
  bool fresh(DateTime now) => successorFresh(checkedAt, validUntil, now);
  factory AdminReceiptSuccessorObservationPage.parse(
    Object? raw,
    AdminReceiptSuccessorExecutionSnapshot snapshot,
    int? after,
    int limit,
  ) {
    if (!snapshot.available || limit < 1 || limit > 50) executionInvalid();
    if (after != null && (cancelRevision(after) > snapshot.cutoff!)) {
      executionInvalid();
    }
    final r = _object(raw, {
      'contract_version',
      'scope',
      'approval_id',
      'primary_receipt_id',
      'cutoff_revision',
      'after_revision',
      'limit',
      'checked_at',
      'sample_valid_until',
      'status',
      'items',
      'next_after_revision',
      ..._limits,
    });
    _contract(r, 'rw_receipt_successor_observations');
    _sample(r);
    if (r['approval_id'] != snapshot.approvalId ||
        r['cutoff_revision'] != snapshot.cutoff ||
        r['after_revision'] != after ||
        r['limit'] != limit) {
      executionInvalid();
    }
    final items = _array(r['items'], limit);
    if (r['status'] == 'unavailable') {
      if (r['primary_receipt_id'] != null ||
          items.isNotEmpty ||
          r['next_after_revision'] != null) {
        executionInvalid();
      }
    } else {
      if (r['status'] != 'available' ||
          r['primary_receipt_id'] != snapshot.primaryReceiptId) {
        executionInvalid();
      }
      final requests = <String>{};
      var previous = after ?? 0;
      for (final item in items) {
        final v = _object(item, {
          'request_id',
          'callback_id',
          'attempt_id',
          'segment_index',
          'callback_kind',
          'result_code',
          'tp_status',
          'occurred_at',
          'recorded_at',
          'lineage_before',
          'lineage_after',
          'observed_state',
        });
        if (!requests.add(cancelUuid(v['request_id'])) ||
            cancelUuid(v['attempt_id']) != snapshot.attemptId) {
          executionInvalid();
        }
        cancelUuid(v['callback_id']);
        final segment = _integer(v['segment_index'], 0, 9);
        if (segment >=
                ((snapshot.execution!['attempt'] as Map)['segment_count']
                    as int) ||
            !{'sent', 'delivery'}.contains(v['callback_kind']) ||
            !_observedStates.contains(v['observed_state'])) {
          executionInvalid();
        }
        _integer(v['result_code'], -1, 200);
        if (v['tp_status'] != null) _integer(v['tp_status'], 0, 255);
        final before = cancelRevision(v['lineage_before']),
            revision = cancelRevision(v['lineage_after']);
        if (revision != before + 1 ||
            revision <= previous ||
            revision > snapshot.cutoff! ||
            cancelInstant(
              v['recorded_at'],
            ).isAfter(cancelInstant(r['checked_at']))) {
          executionInvalid();
        }
        cancelInstant(v['occurred_at']);
        previous = revision;
      }
      if (r['next_after_revision'] != null &&
          (items.length != limit ||
              cancelRevision(r['next_after_revision']) != previous)) {
        executionInvalid();
      }
    }
    return AdminReceiptSuccessorObservationPage._(
      _freeze(r) as Map<String, dynamic>,
    );
  }
}
