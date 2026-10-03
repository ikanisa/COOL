import 'dart:convert';
import 'admin_exception_checkpoint.dart';
import 'admin_exception_models.dart';

int _count(Object? raw, {int minimum = 0}) {
  if (raw is! int || raw < minimum || raw > 1000000000) {
    exceptionInvalid();
  }
  return raw;
}

class AdminExceptionEscalation {
  const AdminExceptionEscalation(
    this.id,
    this.sourceRevision,
    this.recipientId,
    this.state,
    this.queuedAt,
    this.deliveredAt,
    this.readAt,
  );
  final String id, recipientId, state;
  final int sourceRevision;
  final DateTime queuedAt;
  final DateTime? deliveredAt, readAt;
  factory AdminExceptionEscalation.parse(Object? raw) {
    final data = exceptionObject(raw, {
      'id',
      'source_revision',
      'recipient_id',
      'state',
      'queued_at',
      'delivered_at',
      'read_at',
    });
    final state = data['state'];
    if (!{
      'queued',
      'delivered',
      'obsolete',
      'recipient_unavailable',
    }.contains(state)) {
      exceptionInvalid();
    }
    final queued = exceptionInstant(data['queued_at']);
    final delivered = data['delivered_at'] == null
        ? null
        : exceptionInstant(data['delivered_at']);
    final read = data['read_at'] == null
        ? null
        : exceptionInstant(data['read_at']);
    if ((state == 'delivered') != (delivered != null) ||
        delivered != null && delivered.isBefore(queued) ||
        read != null && (delivered == null || read.isBefore(delivered))) {
      exceptionInvalid();
    }
    return AdminExceptionEscalation(
      exceptionUuid(data['id']),
      _count(data['source_revision'], minimum: 1),
      exceptionUuid(data['recipient_id']),
      state as String,
      queued,
      delivered,
      read,
    );
  }
}

class AdminExceptionWorkflow {
  const AdminExceptionWorkflow(
    this.exceptionId,
    this.sourceRevision,
    this.revision,
    this.sourceActive,
    this.assigneeId,
    this.recipientAvailable,
    this.dueAt,
    this.overdue,
    this.status,
    this.escalations,
    this.checkedAt,
    this.validUntil,
  );
  final String exceptionId, status;
  final int sourceRevision, revision;
  final bool sourceActive, recipientAvailable, overdue;
  final String? assigneeId;
  final DateTime? dueAt;
  final List<AdminExceptionEscalation> escalations;
  final DateTime checkedAt, validUntil;
  bool isFresh(DateTime now) =>
      !now.isBefore(checkedAt) && now.isBefore(validUntil);
  factory AdminExceptionWorkflow.parse(Object? raw, String exceptionId) {
    final data = exceptionObject(raw, {
      'contract_version',
      'exception_id',
      'source_revision',
      'source_active',
      'workflow_revision',
      'assignee_id',
      'recipient_available',
      'due_at',
      'overdue',
      'status',
      'escalations',
      'checked_at',
      'sample_valid_until',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        exceptionUuid(data['exception_id']) != exceptionUuid(exceptionId) ||
        data['source_active'] is! bool ||
        data['recipient_available'] is! bool ||
        data['overdue'] is! bool) {
      exceptionInvalid();
    }
    final revision = _count(data['workflow_revision']);
    final assignee = data['assignee_id'] == null
        ? null
        : exceptionUuid(data['assignee_id']);
    final due = data['due_at'] == null
        ? null
        : exceptionInstant(data['due_at']);
    final active = data['source_active'] as bool;
    final status = data['status'];
    if (!{
          'unassigned',
          'assigned',
          'source_cleared',
          'resolved',
        }.contains(status) ||
        revision == 0 && assignee != null ||
        (assignee == null) != (due == null) ||
        revision == 0 &&
            (data['recipient_available'] != false ||
                data['overdue'] != false) ||
        active && !{'unassigned', 'assigned'}.contains(status) ||
        !active && !{'source_cleared', 'resolved'}.contains(status) ||
        status == 'assigned' && assignee == null ||
        status == 'unassigned' && assignee != null ||
        !active && data['overdue'] != false) {
      exceptionInvalid();
    }
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      exceptionInvalid();
    }
    final rawRows = data['escalations'];
    if (rawRows is! List || rawRows.length > 10) {
      exceptionInvalid();
    }
    final rows = rawRows.map(AdminExceptionEscalation.parse).toList();
    if (rows.map((e) => e.id).toSet().length != rows.length ||
        rows.any(
          (e) =>
              e.queuedAt.isAfter(checked) ||
              e.deliveredAt?.isAfter(checked) == true ||
              e.readAt?.isAfter(checked) == true,
        )) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflow(
      exceptionId,
      _count(data['source_revision'], minimum: 1),
      revision,
      active,
      assignee,
      data['recipient_available'] as bool,
      due,
      data['overdue'] as bool,
      status as String,
      List.unmodifiable(rows),
      checked,
      until,
    );
  }
}

class AdminExceptionWorkflowIntent {
  const AdminExceptionWorkflowIntent({
    required this.requestId,
    required this.exceptionId,
    required this.sourceRevision,
    required this.workflowRevision,
    required this.action,
    required this.expiresAt,
    this.assigneeId,
    this.dueAt,
  });
  final String requestId, exceptionId, action;
  final int sourceRevision, workflowRevision;
  final DateTime expiresAt;
  final String? assigneeId;
  final DateTime? dueAt;
  Map<String, dynamic> get parameters => {
    'p_request_id': requestId,
    'p_exception_id': exceptionId,
    'p_expected_source_revision': sourceRevision,
    'p_expected_workflow_revision': workflowRevision,
    'p_action': action,
    'p_assignee_id': assigneeId,
    'p_due_at': dueAt == null ? null : _wire(dueAt!),
    'p_reason_code': action == 'resolve'
        ? 'source_rechecked'
        : action == 'assign'
        ? 'review_started'
        : 'owner_review_required',
    'p_expires_at': _wire(expiresAt),
  };
  factory AdminExceptionWorkflowIntent.parse(Object? raw) {
    final data = exceptionObject(raw, {
      'p_request_id',
      'p_exception_id',
      'p_expected_source_revision',
      'p_expected_workflow_revision',
      'p_action',
      'p_assignee_id',
      'p_due_at',
      'p_reason_code',
      'p_expires_at',
    });
    final action = data['p_action'];
    if (!{'assign', 'escalate', 'resolve'}.contains(action) ||
        data['p_reason_code'] !=
            (action == 'resolve'
                ? 'source_rechecked'
                : action == 'assign'
                ? 'review_started'
                : 'owner_review_required')) {
      exceptionInvalid();
    }
    final assignee = data['p_assignee_id'] == null
        ? null
        : exceptionUuid(data['p_assignee_id']);
    final due = data['p_due_at'] == null
        ? null
        : exceptionInstant(data['p_due_at']);
    if (action == 'assign'
        ? assignee == null || due == null
        : assignee != null || due != null) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflowIntent(
      requestId: exceptionUuid(data['p_request_id']),
      exceptionId: exceptionUuid(data['p_exception_id']),
      sourceRevision: _count(data['p_expected_source_revision'], minimum: 1),
      workflowRevision: _count(data['p_expected_workflow_revision']),
      action: action as String,
      assigneeId: assignee,
      dueAt: due,
      expiresAt: exceptionInstant(data['p_expires_at']),
    );
  }

  /// Keep only the self-assignment marker in recovery storage. The actor UUID
  /// belongs to a fresh authorized identity, rather than a persisted draft.
  String encode(String ownerDigest, String currentActorId) {
    final actor = exceptionUuid(currentActorId);
    if (ownerDigest !=
            adminExceptionOwnerDigest('workflow:$actor:$exceptionId') ||
        (action == 'assign' && assigneeId != actor)) {
      exceptionInvalid();
    }
    AdminExceptionWorkflowIntent.parse(parameters);
    return jsonEncode({
      'version': 2,
      'owner_digest': ownerDigest,
      'request': {
        ...parameters,
        'p_assignee_id': action == 'assign' ? 'self' : null,
      },
    });
  }

  static AdminExceptionWorkflowIntent decode(
    String encoded,
    String ownerDigest,
    String currentActorId,
  ) {
    if (encoded.length > 4096) {
      exceptionInvalid();
    }
    final data = exceptionObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'request',
    });
    if (data['version'] is! int ||
        data['version'] != 2 ||
        data['owner_digest'] != ownerDigest) {
      exceptionInvalid();
    }
    final request = exceptionObject(data['request'], {
      'p_request_id',
      'p_exception_id',
      'p_expected_source_revision',
      'p_expected_workflow_revision',
      'p_action',
      'p_assignee_id',
      'p_due_at',
      'p_reason_code',
      'p_expires_at',
    });
    final actor = exceptionUuid(currentActorId);
    if (request['p_assignee_id'] !=
        (request['p_action'] == 'assign' ? 'self' : null)) {
      exceptionInvalid();
    }
    final intent = AdminExceptionWorkflowIntent.parse({
      ...request,
      'p_assignee_id': request['p_action'] == 'assign' ? actor : null,
    });
    if (ownerDigest !=
        adminExceptionOwnerDigest('workflow:$actor:${intent.exceptionId}')) {
      exceptionInvalid();
    }
    return intent;
  }
}

String _wire(DateTime value) => value
    .toUtc()
    .toIso8601String()
    .replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (match) => '.${match[1]}000Z');

/// Rejected recovery data can retain an opaque original-request reference,
/// but can never become an intent eligible for submission.
class AdminExceptionWorkflowRecovery {
  const AdminExceptionWorkflowRecovery._(
    this.ownerDigest,
    this.exceptionId,
    this._receiptReference,
  );
  final String ownerDigest, exceptionId;
  final AdminExceptionWorkflowIntent? _receiptReference;
  String? get requestId => _receiptReference?.requestId;

  static void _owner(String owner, String actor, String exceptionId) {
    if (owner !=
        adminExceptionOwnerDigest(
          'workflow:${exceptionUuid(actor)}:${exceptionUuid(exceptionId)}',
        )) {
      exceptionInvalid();
    }
  }

  static AdminExceptionWorkflowRecovery scrub(
    String rejected,
    String owner,
    String actor,
    String exceptionId,
  ) {
    _owner(owner, actor, exceptionId);
    AdminExceptionWorkflowIntent? reference;
    try {
      if (rejected.length > 4096) exceptionInvalid();
      final data = jsonDecode(rejected);
      if (data is! Map || data['owner_digest'] != owner) exceptionInvalid();
      final request = data['request'];
      if (request is! Map || request['p_exception_id'] != exceptionId) {
        exceptionInvalid();
      }
      reference = _reference({
        'request_id': request['p_request_id'],
        'exception_id': request['p_exception_id'],
        'source_revision': request['p_expected_source_revision'],
        'workflow_revision': request['p_expected_workflow_revision'],
        'action': request['p_action'],
        'expires_at': request['p_expires_at'],
      }, exceptionId);
    } catch (_) {
      // A malformed or foreign draft still leaves a durable local block, with
      // no unverified request reference and no retained private payload.
    }
    return AdminExceptionWorkflowRecovery._(owner, exceptionId, reference);
  }

  static AdminExceptionWorkflowIntent _reference(Object? raw, String id) {
    final data = exceptionObject(raw, {
      'request_id',
      'exception_id',
      'source_revision',
      'workflow_revision',
      'action',
      'expires_at',
    });
    if (exceptionUuid(data['exception_id']) != id ||
        !{'assign', 'escalate', 'resolve'}.contains(data['action'])) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflowIntent(
      requestId: exceptionUuid(data['request_id']),
      exceptionId: id,
      sourceRevision: _count(data['source_revision'], minimum: 1),
      workflowRevision: _count(data['workflow_revision']),
      action: data['action'] as String,
      expiresAt: exceptionInstant(data['expires_at']),
    );
  }

  factory AdminExceptionWorkflowRecovery.parse(
    String encoded,
    String owner,
    String actor,
    String exceptionId,
  ) {
    _owner(owner, actor, exceptionId);
    if (encoded.length > 4096) exceptionInvalid();
    final data = exceptionObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'exception_id',
      'blocked_reference',
    });
    if (data['version'] is! int ||
        data['version'] != 3 ||
        data['owner_digest'] != owner ||
        data['exception_id'] != exceptionId) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflowRecovery._(
      owner,
      exceptionId,
      data['blocked_reference'] == null
          ? null
          : _reference(data['blocked_reference'], exceptionId),
    );
  }

  String encode() => jsonEncode({
    'version': 3,
    'owner_digest': ownerDigest,
    'exception_id': exceptionId,
    'blocked_reference': _receiptReference == null
        ? null
        : {
            'request_id': _receiptReference.requestId,
            'exception_id': exceptionId,
            'source_revision': _receiptReference.sourceRevision,
            'workflow_revision': _receiptReference.workflowRevision,
            'action': _receiptReference.action,
            'expires_at': _wire(_receiptReference.expiresAt),
          },
  });

  AdminExceptionWorkflowLookup lookup(Object? raw) {
    if (_receiptReference == null) exceptionInvalid();
    return AdminExceptionWorkflowLookup.parse(raw, _receiptReference);
  }
}

class AdminExceptionWorkflowReceipt {
  const AdminExceptionWorkflowReceipt(
    this.requestId,
    this.exceptionId,
    this.action,
    this.sourceRevision,
    this.revision,
    this.escalationId,
    this.recordedAt,
  );
  final String requestId, exceptionId, action;
  final int sourceRevision, revision;
  final String? escalationId;
  final DateTime recordedAt;
  factory AdminExceptionWorkflowReceipt.parse(
    Object? raw,
    AdminExceptionWorkflowIntent intent,
  ) {
    final data = exceptionObject(raw, {
      'contract_version',
      'request_id',
      'exception_id',
      'source_revision',
      'workflow_revision',
      'action',
      'escalation_id',
      'source_resolved',
      'financial_action',
      'send_action',
      'recorded_at',
    });
    final escalation = data['escalation_id'] == null
        ? null
        : exceptionUuid(data['escalation_id']);
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        exceptionUuid(data['request_id']) != intent.requestId ||
        exceptionUuid(data['exception_id']) != intent.exceptionId ||
        _count(data['source_revision'], minimum: 1) != intent.sourceRevision ||
        _count(data['workflow_revision'], minimum: 1) !=
            intent.workflowRevision + 1 ||
        data['action'] != intent.action ||
        data['source_resolved'] != (intent.action == 'resolve') ||
        data['financial_action'] != false ||
        data['send_action'] != false ||
        (intent.action == 'escalate') != (escalation != null)) {
      exceptionInvalid();
    }
    final at = exceptionInstant(data['recorded_at']);
    if (!at.isBefore(intent.expiresAt)) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflowReceipt(
      intent.requestId,
      intent.exceptionId,
      intent.action,
      intent.sourceRevision,
      intent.workflowRevision + 1,
      escalation,
      at,
    );
  }
}

class AdminExceptionWorkflowLookup {
  const AdminExceptionWorkflowLookup(
    this.status,
    this.checkedAt,
    this.validUntil,
    this.receipt,
  );
  final String status;
  final DateTime checkedAt, validUntil;
  final AdminExceptionWorkflowReceipt? receipt;
  factory AdminExceptionWorkflowLookup.parse(
    Object? raw,
    AdminExceptionWorkflowIntent intent,
  ) {
    final data = exceptionObject(raw, {
      'contract_version',
      'request_id',
      'checked_at',
      'sample_valid_until',
      'status',
      'receipt',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        exceptionUuid(data['request_id']) != intent.requestId ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(data['status']) ||
        (data['status'] == 'recorded') != (data['receipt'] != null)) {
      exceptionInvalid();
    }
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    if (until.difference(checked) != const Duration(seconds: 60)) {
      exceptionInvalid();
    }
    return AdminExceptionWorkflowLookup(
      data['status'] as String,
      checked,
      until,
      data['receipt'] == null
          ? null
          : AdminExceptionWorkflowReceipt.parse(data['receipt'], intent),
    );
  }
  bool canClearUnrecorded(AdminExceptionWorkflowIntent intent, DateTime now) =>
      status == 'not_recorded' &&
      !checkedAt.isBefore(intent.expiresAt) &&
      !now.isBefore(checkedAt) &&
      now.isBefore(validUntil);
}

class AdminExceptionInboxDelivery {
  const AdminExceptionInboxDelivery(
    this.id,
    this.exceptionId,
    this.reasonCode,
    this.sourceRevision,
    this.currentSourceRevision,
    this.sourceActive,
    this.deliveredAt,
    this.readAt,
  );
  final String id, exceptionId, reasonCode;
  final int sourceRevision, currentSourceRevision;
  final bool sourceActive;
  final DateTime deliveredAt;
  final DateTime? readAt;
  factory AdminExceptionInboxDelivery.parse(Object? raw, DateTime checked) {
    final data = exceptionObject(raw, {
      'escalation_id',
      'exception_id',
      'source_revision',
      'reason_code',
      'source_active',
      'current_source_revision',
      'delivered_at',
      'read_at',
    });
    final source = _count(data['source_revision'], minimum: 1);
    final current = _count(data['current_source_revision'], minimum: 1);
    final delivered = exceptionInstant(data['delivered_at']);
    final read = data['read_at'] == null
        ? null
        : exceptionInstant(data['read_at']);
    if (!{
          'operator_escalation',
          'deadline_exceeded',
        }.contains(data['reason_code']) ||
        data['source_active'] is! bool ||
        current < source ||
        delivered.isAfter(checked) ||
        read != null && (read.isBefore(delivered) || read.isAfter(checked))) {
      exceptionInvalid();
    }
    return AdminExceptionInboxDelivery(
      exceptionUuid(data['escalation_id']),
      exceptionUuid(data['exception_id']),
      data['reason_code'] as String,
      source,
      current,
      data['source_active'] as bool,
      delivered,
      read,
    );
  }
}

class AdminExceptionEscalationSnapshot {
  const AdminExceptionEscalationSnapshot(
    this.checkedAt,
    this.validUntil,
    this.rows,
  );
  final DateTime checkedAt, validUntil;
  final List<AdminExceptionInboxDelivery> rows;
  bool isFresh(DateTime now) =>
      !now.isBefore(checkedAt) && now.isBefore(validUntil);
  factory AdminExceptionEscalationSnapshot.parse(Object? raw) {
    final data = exceptionObject(raw, {
      'contract_version',
      'channel',
      'checked_at',
      'sample_valid_until',
      'rows',
    });
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        data['channel'] != 'admin_inbox') {
      exceptionInvalid();
    }
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    final values = data['rows'];
    if (until.difference(checked) != const Duration(seconds: 60) ||
        values is! List ||
        values.length > 50) {
      exceptionInvalid();
    }
    final rows = values
        .map((row) => AdminExceptionInboxDelivery.parse(row, checked))
        .toList();
    if (rows.map((row) => row.id).toSet().length != rows.length) {
      exceptionInvalid();
    }
    return AdminExceptionEscalationSnapshot(
      checked,
      until,
      List.unmodifiable(rows),
    );
  }
}
