import 'package:uuid/uuid.dart';

import 'admin_entity_audit.dart';
import 'admin_exception_models.dart';

String _wire(DateTime value) {
  final text = value.toUtc().toIso8601String().replaceFirstMapped(
    RegExp(r'\.(\d{3})Z$'),
    (match) => '.${match[1]}000Z',
  );
  exceptionInstant(text);
  return text;
}

int _revision(Object? value) {
  if (value is! int || value < 1 || value > 1000000000) {
    auditInvalid();
  }
  return value;
}

/// Exception-only v2 input. Other entity kinds remain on their strict v1 API.
Map<String, dynamic> adminExceptionHistoryParameters(
  AdminEntityAuditQuery query,
) {
  query.validate();
  if (query.kind != AdminAuditEntityKind.exception || query.limit > 25) {
    auditInvalid();
  }
  return Map.unmodifiable({
    'p_exception_id': query.id,
    'p_limit': query.limit,
    'p_before_at': query.before == null
        ? null
        : _wire(query.before!.recordedAt),
    'p_before_event_id': query.before?.eventId,
  });
}

const _sourceLabels = {
  'exception_action': 'Review action',
  'exception_workflow_request': 'Follow-up action',
  'exception_escalation_event': 'Escalation event',
};
const _actionLabels = {
  'exception.acknowledge': 'Review acknowledged',
  'exception.escalate': 'Review escalation requested',
  'exception.workflow.assign': 'Follow-up assigned',
  'exception.workflow.escalate': 'Follow-up escalation requested',
  'exception.workflow.resolve': 'Follow-up resolved',
  'exception.escalation.queued': 'Escalation queued',
  'exception.escalation.delivered': 'Escalation delivered to Admin inbox',
  'exception.escalation.opened': 'Escalation opened',
  'exception.escalation.obsolete': 'Escalation obsolete',
  'exception.escalation.recipient_unavailable':
      'Escalation recipient unavailable',
};
const _actorLabels = {
  'operator': 'Operator',
  'service': 'Service',
  'unknown': 'Actor not recorded',
};
const _originLabels = {
  'immutable_request': 'Original recorded request',
  'retained_source': 'Retained source record',
  'captured_transition': 'Captured transition',
};
const _reviewReasons = {
  'review_started': 'Review started',
  'owner_review_required': 'Owner review required',
  'uncertain_send_review': 'Uncertain send review',
  'contact_review': 'Contact review',
};
const _reasonLabels = {
  ..._reviewReasons,
  'source_rechecked': 'Source rechecked',
  'operator_escalation': 'Operator escalation',
  'deadline_exceeded': 'Deadline exceeded',
};

/// Original retained evidence. Delivery/opening, actor attribution and source
/// handling remain separate; rows cannot grant current workflow authority.
class AdminExceptionHistoryEvent {
  const AdminExceptionHistoryEvent._({
    required this.eventId,
    required this.source,
    required this.sourceRecordId,
    required this.action,
    required this.recordedAt,
    required this.actorKind,
    required this.actorId,
    required this.requestId,
    required this.revision,
    required this.workflowRevision,
    required this.escalationId,
    required this.reasonCode,
    required this.origin,
    required this.assigneeId,
    required this.dueAt,
  });
  final String eventId, source, sourceRecordId, action, actorKind, origin;
  final DateTime recordedAt;
  final String? actorId, requestId, escalationId, reasonCode, assigneeId;
  final int revision;
  final int? workflowRevision;
  final DateTime? dueAt;
  String get sourceLabel => _sourceLabels[source]!;
  String get actionLabel => _actionLabels[action]!;
  String get actorKindLabel => _actorLabels[actorKind]!;
  String get originLabel => _originLabels[origin]!;
  String? get reasonLabel =>
      reasonCode == null ? null : _reasonLabels[reasonCode];
  AdminEntityAuditCursor get cursor =>
      AdminEntityAuditCursor(recordedAt: recordedAt, eventId: eventId);

  factory AdminExceptionHistoryEvent.parse(Object? raw) {
    final row = exceptionObject(raw, {
      'event_id',
      'source',
      'source_record_id',
      'action',
      'recorded_at',
      'actor_kind',
      'actor_id',
      'request_id',
      'revision',
      'workflow_revision',
      'escalation_id',
      'reason_code',
      'origin',
      'assignee_id',
      'due_at',
    });
    final source = row['source'],
        action = row['action'],
        actor = row['actor_kind'],
        origin = row['origin'],
        reason = row['reason_code'];
    if (source is! String ||
        !_sourceLabels.containsKey(source) ||
        action is! String ||
        !_actionLabels.containsKey(action) ||
        actor is! String ||
        !_actorLabels.containsKey(actor) ||
        origin is! String ||
        !_originLabels.containsKey(origin) ||
        reason is! String ||
        !_reasonLabels.containsKey(reason)) {
      auditInvalid();
    }
    final eventId = auditUuid(row['event_id']),
        recordId = auditUuid(row['source_record_id']);
    if (eventId !=
        const Uuid().v5(
          'c5a97546-80ab-5b57-a267-754aac043bd0',
          '$source:$recordId',
        )) {
      auditInvalid();
    }
    final actorId = row['actor_id'] == null ? null : auditUuid(row['actor_id']);
    final request = row['request_id'] == null
        ? null
        : auditUuid(row['request_id']);
    final escalation = row['escalation_id'] == null
        ? null
        : auditUuid(row['escalation_id']);
    final assignee = row['assignee_id'] == null
        ? null
        : auditUuid(row['assignee_id']);
    final due = row['due_at'] == null ? null : exceptionInstant(row['due_at']);
    final workflow = row['workflow_revision'] == null
        ? null
        : _revision(row['workflow_revision']);
    if ((actor == 'operator') != (actorId != null)) {
      auditInvalid();
    }
    switch (source) {
      case 'exception_action':
        if (!{'exception.acknowledge', 'exception.escalate'}.contains(action) ||
            actor != 'operator' ||
            request != recordId ||
            origin != 'immutable_request' ||
            workflow != null ||
            escalation != null ||
            assignee != null ||
            due != null ||
            !_reviewReasons.containsKey(reason)) {
          auditInvalid();
        }
      case 'exception_workflow_request':
        if (!{
              'exception.workflow.assign',
              'exception.workflow.escalate',
              'exception.workflow.resolve',
            }.contains(action) ||
            actor != 'operator' ||
            request != recordId ||
            origin != 'immutable_request' ||
            workflow == null ||
            (action == 'exception.workflow.escalate') != (escalation != null) ||
            (action == 'exception.workflow.assign') != (assignee != null) ||
            (action == 'exception.workflow.assign') != (due != null) ||
            action == 'exception.workflow.resolve' &&
                reason != 'source_rechecked' ||
            !_reviewReasons.containsKey(reason) &&
                reason != 'source_rechecked') {
          auditInvalid();
        }
      case 'exception_escalation_event':
        if (!{
              'exception.escalation.queued',
              'exception.escalation.delivered',
              'exception.escalation.opened',
              'exception.escalation.obsolete',
              'exception.escalation.recipient_unavailable',
            }.contains(action) ||
            request != null ||
            workflow != null ||
            escalation == null ||
            assignee != null ||
            due != null ||
            !{'operator_escalation', 'deadline_exceeded'}.contains(reason) ||
            origin == 'immutable_request' ||
            origin == 'retained_source' && actor != 'unknown') {
          auditInvalid();
        }
    }
    return AdminExceptionHistoryEvent._(
      eventId: eventId,
      source: source,
      sourceRecordId: recordId,
      action: action,
      recordedAt: exceptionInstant(row['recorded_at']),
      actorKind: actor,
      actorId: actorId,
      requestId: request,
      revision: _revision(row['revision']),
      workflowRevision: workflow,
      escalationId: escalation,
      reasonCode: reason,
      origin: origin,
      assigneeId: assignee,
      dueAt: due,
    );
  }
}

class AdminExceptionHistorySnapshot {
  const AdminExceptionHistorySnapshot._({
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
  final List<AdminExceptionHistoryEvent> rows;
  final AdminEntityAuditCursor? nextCursor;
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);
  factory AdminExceptionHistorySnapshot.parse(
    Object? raw, {
    required AdminEntityAuditQuery query,
  }) {
    adminExceptionHistoryParameters(query);
    final row = exceptionObject(raw, {
      'contract_version',
      'scope',
      'entity_kind',
      'entity_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'limit',
      'history_complete',
      'financial_action',
      'send_action',
      'rows',
      'next_cursor',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        row['scope'] != 'rw_operator_entity_audit' ||
        row['entity_kind'] != 'exception' ||
        row['entity_id'] != query.id ||
        row['limit'] is! int ||
        row['limit'] != query.limit ||
        !{'available', 'unavailable'}.contains(row['status']) ||
        row['history_complete'] != false ||
        row['financial_action'] != false ||
        row['send_action'] != false) {
      auditInvalid();
    }
    final checked = exceptionInstant(row['checked_at']),
        until = exceptionInstant(row['sample_valid_until']);
    final list = row['rows'];
    if (until.difference(checked) != const Duration(seconds: 60) ||
        list is! List ||
        list.length > query.limit) {
      auditInvalid();
    }
    final rows = list.map(AdminExceptionHistoryEvent.parse).toList();
    final ids = <String>{};
    AdminEntityAuditCursor? previous = query.before;
    for (final event in rows) {
      if (!ids.add(event.eventId) ||
          event.recordedAt.isAfter(checked) ||
          previous != null && event.cursor.compareTo(previous) >= 0) {
        auditInvalid();
      }
      previous = event.cursor;
    }
    final cursor = row['next_cursor'] == null
        ? null
        : exceptionObject(row['next_cursor'], {'recorded_at', 'event_id'});
    final next = cursor == null
        ? null
        : AdminEntityAuditCursor(
            recordedAt: exceptionInstant(cursor['recorded_at']),
            eventId: auditUuid(cursor['event_id']),
          );
    if (row['status'] == 'unavailable' && (rows.isNotEmpty || next != null) ||
        next != null && (rows.length != query.limit || next != previous)) {
      auditInvalid();
    }
    return AdminExceptionHistorySnapshot._(
      query: query,
      available: row['status'] == 'available',
      checkedAt: checked,
      validUntil: until,
      rows: List.unmodifiable(rows),
      nextCursor: next,
    );
  }
}
