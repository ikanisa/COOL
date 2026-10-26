import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_models.dart';

import 'admin_entity_audit_fixture.dart';

const adminAuditStateRoute = '/admin/audit-logs/entity/:kind/:id';
const adminAuditStateId = auditFixtureEntityId;

String adminAuditStatePath(String route, String fallbackId) => route
    .replaceAll(':kind', 'gateway_device')
    .replaceAll(
      ':id',
      route == adminAuditStateRoute ? adminAuditStateId : fallbackId,
    );

AdminIdentity adminAuditStateIdentity(AdminIdentity original) => AdminIdentity(
  userId: original.userId,
  displayName: original.displayName,
  roles: const ['platform_owner'],
  permissions: original.permissions,
);

class AdminAuditStateSessions extends AdminSessionController {
  AdminAuditStateSessions(String userId) : super(null) {
    state = (
      key: (userId: userId, sessionId: 'synthetic-declared-audit-route'),
      generation: 1,
    );
  }
}

/// Authored presentation fixture with a controlled clock and exact target.
/// This does not assert a hosted server result.
Map<String, dynamic> adminAuditStateFixture(
  DateTime now,
  AdminEntityAuditQuery query, {
  bool empty = false,
}) {
  final raw = auditObserved('gateway');
  final delta = now.toUtc().difference(
    DateTime.parse(raw['checked_at'] as String),
  );
  String stamp(DateTime value) => value
      .toUtc()
      .toIso8601String()
      .replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (m) => '.${m[1]}000Z');
  Object? shift(Object? value) {
    if (value is Map) {
      return {for (final entry in value.entries) entry.key: shift(entry.value)};
    }
    if (value is List) return value.map(shift).toList();
    if (value is String && RegExp(r'^\d{4}-.*T.*Z$').hasMatch(value)) {
      return stamp(DateTime.parse(value).add(delta));
    }
    return value;
  }

  final shifted = Map<String, dynamic>.from(shift(raw) as Map);
  if (empty) {
    shifted['rows'] = <Object>[];
  }
  return auditWindow(shifted, query);
}
