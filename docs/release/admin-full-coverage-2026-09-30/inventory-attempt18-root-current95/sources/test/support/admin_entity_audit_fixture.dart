import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_entity_audit.dart';

Map<String, dynamic> auditObserved([String name = 'shadow']) =>
    jsonDecode(
          File(
            'test/fixtures/admin_entity_audit/observed-$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
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
