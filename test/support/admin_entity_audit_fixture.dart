import 'dart:convert';

import 'package:collect_app/admin/core/admin_entity_audit.dart';

// Authored parser and client DTO doubles; no backend execution is represented.
const auditFixtureEntityId = '72200000-0000-4000-8000-000000000020';
Map<String, dynamic> auditObserved([String name = 'shadow']) {
  const configs = {
    'shadow': (
      'shadow_run',
      'shadow_audit_event',
      ['shadow.completed', 'shadow.sampled', 'shadow.started'],
    ),
    'expiry': ('shadow_run', 'shadow_audit_event', ['shadow.expired']),
    'gateway': (
      'gateway_device',
      'gateway_admin_request',
      ['gateway.revoke', 'gateway.enroll'],
    ),
    'supervisor': (
      'supervisor_identity',
      'supervisor_owner_request',
      ['supervisor.revoke', 'supervisor.enroll'],
    ),
    'exception': (
      'exception',
      'exception_action',
      ['exception.escalate', 'exception.acknowledge'],
    ),
    'receipt': (
      'receipt',
      'receipt_cancellation',
      ['receipt.cancel_unstarted'],
    ),
  };
  final (kind, source, actions) = configs[name]!;
  final rows = List.generate(actions.length, (index) {
    final eventId =
        '72200000-0000-4000-8000-${(actions.length - index).toString().padLeft(12, '0')}';
    return <String, dynamic>{
      'action': actions[index],
      'source': source,
      'actor_id': '72200000-0000-4000-8000-000000000010',
      'event_id': eventId,
      'revision': name == 'exception'
          ? 1
          : name == 'receipt'
          ? 2
          : null,
      'request_id': source == 'shadow_audit_event'
          ? '72200000-0000-4000-8000-000000000011'
          : eventId,
      'reason_code': name == 'exception'
          ? index == 0
                ? 'owner_review_required'
                : 'review_started'
          : name == 'receipt'
          ? 'operator_cancelled'
          : null,
      'recorded_at': DateTime.utc(2026, 10, 1, 0, 30)
          .subtract(Duration(seconds: index))
          .toIso8601String()
          .replaceFirst('.000Z', '.000000Z'),
      'fence_version': source == 'shadow_audit_event' ? 1001 : null,
    };
  });
  return {
    'rows': rows,
    'limit': 20,
    'scope': 'rw_operator_entity_audit',
    'status': 'available',
    'entity_id': auditFixtureEntityId,
    'checked_at': '2026-10-01T00:31:00.000000Z',
    'entity_kind': kind,
    'next_cursor': null,
    'send_action': false,
    'contract_version': 1,
    'financial_action': false,
    'history_complete': false,
    'sample_valid_until': '2026-10-01T00:32:00.000000Z',
    'historical_shadow_audit_backfilled': false,
  };
}

Map<String, dynamic> auditCopy(Map<String, dynamic> raw) =>
    jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
AdminEntityAuditQuery auditQuery(
  Map<String, dynamic> raw, {
  int? limit,
  AdminEntityAuditCursor? before,
}) => AdminEntityAuditQuery(
  kind: AdminAuditEntityKind.parse(raw['entity_kind']),
  id: raw['entity_id'] as String,
  limit: limit ?? raw['limit'] as int,
  before: before,
);
Map<String, dynamic> auditWindow(
  Map<String, dynamic> raw,
  AdminEntityAuditQuery query,
) {
  final available = raw['status'] == 'available';
  final candidates = (raw['rows'] as List).where((value) {
    if (query.before == null) return true;
    final row = value as Map;
    return AdminEntityAuditCursor(
          recordedAt: DateTime.parse(row['recorded_at'] as String),
          eventId: row['event_id'] as String,
        ).compareTo(query.before!) <
        0;
  }).toList();
  final rows = candidates.take(query.limit).toList();
  return auditCopy(raw)
    ..['limit'] = query.limit
    ..['rows'] = rows
    ..['next_cursor'] = !available || candidates.length <= query.limit
        ? null
        : {
            'recorded_at': (rows.last as Map)['recorded_at'],
            'event_id': (rows.last as Map)['event_id'],
          };
}
