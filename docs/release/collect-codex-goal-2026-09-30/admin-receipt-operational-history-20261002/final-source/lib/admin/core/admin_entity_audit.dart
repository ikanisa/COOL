import '../../core/data/exact_json_values.dart';
import 'admin_models.dart';

Never auditInvalid() =>
    throw const FormatException('Action history could not be validated.');

String auditUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    auditInvalid();
  }
  return value;
}

Map<Object?, Object?> _object(Object? value, Set<String> names) {
  if (value is! Map ||
      value.length != names.length ||
      value.keys.any((key) => key is! String || !names.contains(key))) {
    auditInvalid();
  }
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
      ).hasMatch(value)) {
    auditInvalid();
  }
  try {
    final result = exactJsonTimestamp(value, field: 'action history timestamp');
    if (result.year < 1 || result.year > 9999) {
      auditInvalid();
    }
    return result;
  } on FormatException {
    auditInvalid();
  }
}

int _revision(Object? value) {
  if (value is! int || value < 1 || value > 1000000000) {
    auditInvalid();
  }
  return value;
}

enum AdminAuditEntityKind {
  shadowRun('shadow_run', 'Manual shadow run', 'shadow_audit_event'),
  gatewayDevice(
    'gateway_device',
    'SMS Gateway device',
    'gateway_admin_request',
  ),
  supervisorIdentity(
    'supervisor_identity',
    'Supervisor identity',
    'supervisor_owner_request',
  ),
  exception('exception', 'Operational exception', 'exception_action'),
  receipt('receipt', 'SMS receipt', 'receipt_cancellation'),
  receiptOperationsPolicy(
    'receipt_operations_policy',
    'Receipt operations policy',
    'receipt_operations_owner_request',
  ),
  receiptOperationRun(
    'receipt_operation_run',
    'Operational receipt run',
    'receipt_operations_service_request',
  );

  const AdminAuditEntityKind(this.wire, this.label, this.source);
  final String wire, label, source;

  static AdminAuditEntityKind parse(Object? value) =>
      values.firstWhere((kind) => kind.wire == value, orElse: auditInvalid);

  Set<String> get requiredPermissions => {
    'audit.read',
    'system_health.read',
    'notifications.read',
    if (this == exception ||
        this == receipt ||
        this == receiptOperationsPolicy ||
        this == receiptOperationRun)
      'payments.read',
  };

  bool get hasRevision =>
      this == exception || this == receipt || this == receiptOperationsPolicy;
  bool get hasReason => this == exception || this == receipt;
  bool supportsSource(Object? value) =>
      value == source ||
      this == supervisorIdentity &&
          {
            'receipt_operations_owner_request',
            'receipt_operations_enrollment_workflow',
          }.contains(value);
  bool get hasFence => this == shadowRun || this == receiptOperationRun;
  Map<String, String> get actions => switch (this) {
    shadowRun => {
      'shadow.started': 'Monitoring started',
      'shadow.sampled': 'Observation recorded',
      'shadow.completed': 'Monitoring finished',
      'shadow.expired': 'Run expired',
    },
    gatewayDevice => {
      'gateway.enroll': 'Device enrolled',
      'gateway.activate': 'Device activated',
      'gateway.revoke': 'Device revoked',
    },
    supervisorIdentity => {
      'supervisor.enroll': 'Identity enrolled',
      'supervisor.activate': 'Identity activated',
      'supervisor.revoke': 'Identity revoked',
      'supervisor.operations.enroll': 'Operations identity enrolled',
      'supervisor.operations.activate': 'Operations identity activated',
      'supervisor.operations.revoke': 'Operations identity revoked',
    },
    exception => {
      'exception.acknowledge': 'Review acknowledged',
      'exception.escalate': 'Review escalation requested',
    },
    receipt => {'receipt.cancel_unstarted': 'Unstarted receipt cancelled'},
    receiptOperationRun => {
      'operations.begin_run': 'Run started',
      'operations.list_events': 'Events assigned',
      'operations.ensure_receipt': 'Event outcome recorded',
      'operations.reconcile_backlog': 'Backlog checked',
      'operations.complete_run': 'Original closure summary recorded',
    },
    receiptOperationsPolicy => {
      'supervisor.operations.configure': 'Operations policy configured',
      'supervisor.operations.stop': 'Operations stopped',
    },
  };
}

bool adminEntityAuditCanRead(
  AdminIdentity? identity,
  AdminAuditEntityKind kind,
) =>
    identity != null &&
    identity.roles.contains('platform_owner') &&
    kind.requiredPermissions.every(identity.permissions.contains);

String adminEntityAuditPath(AdminAuditEntityKind kind, String id) =>
    '/admin/audit-logs/entity/${kind.wire}/${auditUuid(id)}';

class AdminEntityAuditCursor {
  const AdminEntityAuditCursor({
    required this.recordedAt,
    required this.eventId,
  });
  final DateTime recordedAt;
  final String eventId;
  int compareTo(AdminEntityAuditCursor other) {
    final time = recordedAt.toUtc().compareTo(other.recordedAt.toUtc());
    return time == 0 ? eventId.compareTo(other.eventId) : time;
  }

  @override
  bool operator ==(Object other) =>
      other is AdminEntityAuditCursor &&
      other.recordedAt == recordedAt &&
      other.eventId == eventId;
  @override
  int get hashCode => Object.hash(recordedAt, eventId);
  factory AdminEntityAuditCursor._parse(Object? raw) {
    final row = _object(raw, {'recorded_at', 'event_id'});
    return AdminEntityAuditCursor(
      recordedAt: _instant(row['recorded_at']),
      eventId: auditUuid(row['event_id']),
    );
  }
}

class AdminEntityAuditQuery {
  const AdminEntityAuditQuery({
    required this.kind,
    required this.id,
    this.limit = 20,
    this.before,
  });
  final AdminAuditEntityKind kind;
  final String id;
  final int limit;
  final AdminEntityAuditCursor? before;
  void validate() {
    auditUuid(id);
    if (limit < 1 || limit > 50) {
      auditInvalid();
    }
    if (before case final cursor?) {
      auditUuid(cursor.eventId);
      if (cursor.recordedAt.toUtc().year < 1 ||
          cursor.recordedAt.toUtc().year > 9999) {
        auditInvalid();
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AdminEntityAuditQuery &&
      other.kind == kind &&
      other.id == id &&
      other.limit == limit &&
      other.before == before;
  @override
  int get hashCode => Object.hash(kind, id, limit, before);
}

const _exceptionReasons = {
  'review_started': 'Review started',
  'owner_review_required': 'Owner review required',
  'uncertain_send_review': 'Uncertain send review',
  'contact_review': 'Contact review',
};
const _receiptReasons = {
  'operator_cancelled': 'Operator cancelled',
  'recipient_review_required': 'Recipient review required',
  'content_review_required': 'Content review required',
};

class AdminEntityAuditEvent {
  const AdminEntityAuditEvent._({
    required this.eventId,
    required this.source,
    required this.action,
    required this.actionLabel,
    required this.recordedAt,
    required this.actorId,
    required this.requestId,
    required this.revision,
    required this.fenceVersion,
    required this.reasonCode,
    required this.reasonLabel,
  });
  final String eventId, source, action, actionLabel, requestId;
  final DateTime recordedAt;
  final String? actorId, reasonCode, reasonLabel;
  final int? revision, fenceVersion;
  AdminEntityAuditCursor get cursor =>
      AdminEntityAuditCursor(recordedAt: recordedAt, eventId: eventId);

  factory AdminEntityAuditEvent._parse(Object? raw, AdminAuditEntityKind kind) {
    final row = _object(raw, {
      'event_id',
      'source',
      'action',
      'recorded_at',
      'actor_id',
      'request_id',
      'revision',
      'fence_version',
      'reason_code',
    });
    final eventId = auditUuid(row['event_id']),
        requestId = auditUuid(row['request_id']);
    final action = row['action'];
    if (!kind.supportsSource(row['source']) ||
        action is! String ||
        !kind.actions.containsKey(action) ||
        (kind != AdminAuditEntityKind.shadowRun &&
            !{
              'receipt_operations_owner_request',
              'receipt_operations_enrollment_workflow',
              'receipt_operations_service_request',
            }.contains(row['source']) &&
            eventId != requestId)) {
      auditInvalid();
    }
    final source = row['source'];
    if (source == 'receipt_operations_service_request' &&
            row['actor_id'] != null ||
        {
              'receipt_operations_owner_request',
              'receipt_operations_enrollment_workflow',
            }.contains(source) &&
            !action.startsWith('supervisor.operations.') ||
        kind == AdminAuditEntityKind.supervisorIdentity &&
            source == kind.source &&
            action.startsWith('supervisor.operations.')) {
      auditInvalid();
    }
    final actorId = row['actor_id'] == null ? null : auditUuid(row['actor_id']);
    if (kind != AdminAuditEntityKind.shadowRun &&
        kind != AdminAuditEntityKind.receiptOperationRun &&
        actorId == null) {
      auditInvalid();
    }
    final revision = row['revision'] == null
        ? null
        : _revision(row['revision']);
    final fence = row['fence_version'] == null
        ? null
        : _revision(row['fence_version']);
    if (kind.hasRevision != (revision != null) ||
        kind.hasFence != (fence != null)) {
      auditInvalid();
    }
    final reasons = kind == AdminAuditEntityKind.exception
        ? _exceptionReasons
        : _receiptReasons;
    final reason = row['reason_code'];
    if (kind.hasReason
        ? reason is! String || !reasons.containsKey(reason)
        : reason != null) {
      auditInvalid();
    }
    return AdminEntityAuditEvent._(
      eventId: eventId,
      source: row['source'] as String,
      action: action,
      actionLabel: kind.actions[action]!,
      recordedAt: _instant(row['recorded_at']),
      actorId: actorId,
      requestId: requestId,
      revision: revision,
      fenceVersion: fence,
      reasonCode: reason as String?,
      reasonLabel: reason == null ? null : reasons[reason],
    );
  }
}

class AdminEntityAuditSnapshot {
  const AdminEntityAuditSnapshot._({
    required this.query,
    required this.available,
    required this.checkedAt,
    required this.validUntil,
    required this.rows,
    required this.nextCursor,
  });
  final AdminEntityAuditQuery query;
  final bool available;
  final DateTime checkedAt, validUntil;
  final List<AdminEntityAuditEvent> rows;
  final AdminEntityAuditCursor? nextCursor;
  factory AdminEntityAuditSnapshot.parse(
    Object? raw, {
    required AdminEntityAuditQuery query,
  }) {
    query.validate();
    final row = _object(raw, {
      'contract_version',
      'scope',
      'entity_kind',
      'entity_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'limit',
      'history_complete',
      'historical_shadow_audit_backfilled',
      'financial_action',
      'send_action',
      'rows',
      'next_cursor',
    });
    final status = row['status'];
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        row['scope'] != 'rw_operator_entity_audit' ||
        row['entity_kind'] != query.kind.wire ||
        row['entity_id'] != query.id ||
        row['limit'] is! int ||
        row['limit'] != query.limit ||
        status != 'available' && status != 'unavailable' ||
        row['history_complete'] != false ||
        row['historical_shadow_audit_backfilled'] != false ||
        row['financial_action'] != false ||
        row['send_action'] != false) {
      auditInvalid();
    }
    final checked = _instant(row['checked_at']),
        until = _instant(row['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      auditInvalid();
    }
    final rawRows = row['rows'];
    if (rawRows is! List || rawRows.length > query.limit) {
      auditInvalid();
    }
    final rows = <AdminEntityAuditEvent>[];
    final ids = <String>{};
    for (final rawEvent in rawRows) {
      final event = AdminEntityAuditEvent._parse(rawEvent, query.kind);
      if (!ids.add(event.eventId) ||
          event.recordedAt.isAfter(checked) ||
          rows.isNotEmpty && event.cursor.compareTo(rows.last.cursor) >= 0 ||
          query.before != null && event.cursor.compareTo(query.before!) >= 0) {
        auditInvalid();
      }
      rows.add(event);
    }
    final next = row['next_cursor'] == null
        ? null
        : AdminEntityAuditCursor._parse(row['next_cursor']);
    if (status == 'unavailable' && (rows.isNotEmpty || next != null) ||
        next != null &&
            (rows.length != query.limit || next != rows.last.cursor)) {
      auditInvalid();
    }
    return AdminEntityAuditSnapshot._(
      query: query,
      available: status == 'available',
      checkedAt: checked,
      validUntil: until,
      rows: List.unmodifiable(rows),
      nextCursor: next,
    );
  }
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);
}
