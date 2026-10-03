import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'admin_exception_checkpoint.dart';
import 'admin_exception_models.dart';
import 'admin_exception_workflow_models.dart';

String _wire(DateTime value) {
  final text = value.toUtc().toIso8601String().replaceFirstMapped(
    RegExp(r'\.(\d{3})Z$'),
    (match) => '.${match[1]}000Z',
  );
  exceptionInstant(text);
  return text;
}

int _revision(Object? value, {int minimum = 0, int maximum = 1000000000}) {
  if (value is! int || value < minimum || value > maximum) {
    exceptionInvalid();
  }
  return value;
}

String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    exceptionInvalid();
  }
  return value;
}

String _action(Object? value) {
  if (value is! String || !{'assign', 'escalate', 'resolve'}.contains(value)) {
    exceptionInvalid();
  }
  return value;
}

({DateTime checked, DateTime until}) _sample(Map<String, dynamic> row) {
  final checked = exceptionInstant(row['checked_at']),
      until = exceptionInstant(row['sample_valid_until']);
  if (until.difference(checked) != const Duration(seconds: 60)) {
    exceptionInvalid();
  }
  return (checked: checked, until: until);
}

bool _fresh(DateTime checked, DateTime until, DateTime now) =>
    !checked.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
    now.toUtc().isBefore(until);

AdminExceptionWorkflowIntent _validatedIntent(
  AdminExceptionWorkflowIntent intent,
) {
  final validated = AdminExceptionWorkflowIntent.parse(intent.parameters);
  _revision(validated.workflowRevision, maximum: 999999999);
  return validated;
}

/// Hashes the exact server grammar: ten lines, no leading/trailing newline.
/// Assignee and deadline remain live input only, outside recovery metadata.
String adminExceptionFollowupFingerprint(AdminExceptionWorkflowIntent intent) {
  final validated = _validatedIntent(intent), parameters = validated.parameters;
  return sha256
      .convert(
        utf8.encode(
          [
            'collect-exception-workflow-v2',
            validated.requestId,
            validated.exceptionId,
            validated.sourceRevision.toString(),
            validated.workflowRevision.toString(),
            validated.action,
            validated.assigneeId ?? '-',
            validated.dueAt == null ? '-' : _wire(validated.dueAt!),
            parameters['p_reason_code'] as String,
            _wire(validated.expiresAt),
          ].join('\n'),
        ),
      )
      .toString();
}

/// An original receipt binding. It has no assignment, due date, reason or
/// mutation parameters, and cannot reconstruct a submit-capable full action.
class AdminExceptionFollowupReference {
  const AdminExceptionFollowupReference._({
    required this.requestId,
    required this.exceptionId,
    required this.sourceRevision,
    required this.workflowRevision,
    required this.action,
    required this.expiresAt,
    required this.requestFingerprint,
  });
  final String requestId, exceptionId, action, requestFingerprint;
  final int sourceRevision, workflowRevision;
  final DateTime expiresAt;

  factory AdminExceptionFollowupReference.fromIntent(
    AdminExceptionWorkflowIntent intent,
  ) {
    final validated = _validatedIntent(intent);
    return AdminExceptionFollowupReference._(
      requestId: validated.requestId,
      exceptionId: validated.exceptionId,
      sourceRevision: validated.sourceRevision,
      workflowRevision: validated.workflowRevision,
      action: validated.action,
      expiresAt: validated.expiresAt,
      requestFingerprint: adminExceptionFollowupFingerprint(validated),
    );
  }

  factory AdminExceptionFollowupReference.parse(Object? raw) {
    final row = exceptionObject(raw, {
      'p_request_id',
      'p_exception_id',
      'p_expected_source_revision',
      'p_expected_workflow_revision',
      'p_action',
      'p_expires_at',
      'request_fingerprint',
    });
    return AdminExceptionFollowupReference._(
      requestId: exceptionUuid(row['p_request_id']),
      exceptionId: exceptionUuid(row['p_exception_id']),
      sourceRevision: _revision(row['p_expected_source_revision'], minimum: 1),
      workflowRevision: _revision(
        row['p_expected_workflow_revision'],
        maximum: 999999999,
      ),
      action: _action(row['p_action']),
      expiresAt: exceptionInstant(row['p_expires_at']),
      requestFingerprint: _digest(row['request_fingerprint']),
    );
  }

  Map<String, dynamic> toJson() => Map.unmodifiable({
    'p_request_id': requestId,
    'p_exception_id': exceptionId,
    'p_expected_source_revision': sourceRevision,
    'p_expected_workflow_revision': workflowRevision,
    'p_action': action,
    'p_expires_at': _wire(expiresAt),
    'request_fingerprint': requestFingerprint,
  });

  Map<String, dynamic> get lookupParameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_request_fingerprint': requestFingerprint,
    'p_expires_at': _wire(expiresAt),
  });
}

class AdminExceptionFollowupBookmark {
  const AdminExceptionFollowupBookmark._(this.ownerDigest, this.reference);
  final String ownerDigest;
  final AdminExceptionFollowupReference reference;

  static void _owner(String owner, String actor, String exceptionId) {
    if (_digest(owner) !=
        adminExceptionOwnerDigest(
          'workflow:${exceptionUuid(actor)}:${exceptionUuid(exceptionId)}',
        )) {
      exceptionInvalid();
    }
  }

  factory AdminExceptionFollowupBookmark.fromIntent(
    AdminExceptionWorkflowIntent intent,
    String ownerDigest,
    String currentActorId,
  ) {
    final reference = AdminExceptionFollowupReference.fromIntent(intent);
    _owner(ownerDigest, currentActorId, reference.exceptionId);
    return AdminExceptionFollowupBookmark._(ownerDigest, reference);
  }

  static AdminExceptionFollowupBookmark decode(
    String encoded,
    String ownerDigest,
    String currentActorId,
    String exceptionId,
  ) {
    _owner(ownerDigest, currentActorId, exceptionId);
    if (utf8.encode(encoded).length > 2048) {
      exceptionInvalid();
    }
    final row = exceptionObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'request',
    });
    if (row['version'] is! int ||
        row['version'] != 3 ||
        row['owner_digest'] != ownerDigest) {
      exceptionInvalid();
    }
    final reference = AdminExceptionFollowupReference.parse(row['request']);
    if (reference.exceptionId != exceptionId) {
      exceptionInvalid();
    }
    final bookmark = AdminExceptionFollowupBookmark._(ownerDigest, reference);
    // Reject duplicate JSON members and noncanonical/restored private drafts.
    if (bookmark.encode() != encoded) {
      exceptionInvalid();
    }
    return bookmark;
  }

  String encode() => jsonEncode({
    'version': 3,
    'owner_digest': ownerDigest,
    'request': reference.toJson(),
  });
  AdminExceptionFollowupReceipt receipt(Object? raw) =>
      AdminExceptionFollowupReceipt.parse(raw, reference);
  AdminExceptionFollowupLookup lookup(Object? raw) =>
      AdminExceptionFollowupLookup.parse(raw, reference);
}

/// Sanitized evidence of rejected v3 metadata. Even a retained valid original
/// binding authorizes only manual v2 recorded-proof investigation; absence
/// cannot clear corruption or reconstruct an action. Missing/bad fingerprints
/// retain at most an opaque request UUID and remain permanently blocked.
class AdminExceptionFollowupQuarantine {
  const AdminExceptionFollowupQuarantine._(
    this.ownerDigest,
    this.exceptionId,
    this.reference,
    this.requestId,
  );
  final String ownerDigest, exceptionId;
  final AdminExceptionFollowupReference? reference;
  final String? requestId;

  static AdminExceptionFollowupQuarantine scrub(
    String encoded,
    String ownerDigest,
    String currentActorId,
    String exceptionId,
  ) {
    AdminExceptionFollowupBookmark._owner(
      ownerDigest,
      currentActorId,
      exceptionId,
    );
    String? requestId;
    AdminExceptionFollowupReference? reference;
    try {
      if (utf8.encode(encoded).length <= 16384) {
        final row = jsonDecode(encoded);
        if (row is Map &&
            row['version'] is int &&
            row['version'] == 3 &&
            row['owner_digest'] == ownerDigest &&
            row['request'] is Map) {
          final request = row['request'] as Map;
          if (exceptionUuid(request['p_exception_id']) == exceptionId) {
            requestId = exceptionUuid(request['p_request_id']);
            try {
              reference = AdminExceptionFollowupReference.parse({
                'p_request_id': request['p_request_id'],
                'p_exception_id': request['p_exception_id'],
                'p_expected_source_revision':
                    request['p_expected_source_revision'],
                'p_expected_workflow_revision':
                    request['p_expected_workflow_revision'],
                'p_action': request['p_action'],
                'p_expires_at': request['p_expires_at'],
                'request_fingerprint': request['request_fingerprint'],
              });
            } on Object {
              // Do not replace a missing/invalid fingerprint or fabricate a
              // legacy identity-only lookup intent from incomplete metadata.
            }
          }
        }
      }
    } on Object {
      // Rejected storage is represented without retaining any raw bytes.
    }
    return AdminExceptionFollowupQuarantine._(
      ownerDigest,
      exceptionId,
      reference,
      requestId,
    );
  }

  static AdminExceptionFollowupQuarantine parse(
    String encoded,
    String ownerDigest,
    String currentActorId,
    String exceptionId,
  ) {
    AdminExceptionFollowupBookmark._owner(
      ownerDigest,
      currentActorId,
      exceptionId,
    );
    if (utf8.encode(encoded).length > 2048) {
      exceptionInvalid();
    }
    final row = exceptionObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'exception_id',
      'original_reference',
      'original_request_id',
    });
    if (row['version'] is! int ||
        row['version'] != 4 ||
        row['owner_digest'] != ownerDigest ||
        exceptionUuid(row['exception_id']) != exceptionId) {
      exceptionInvalid();
    }
    final reference = row['original_reference'] == null
        ? null
        : AdminExceptionFollowupReference.parse(row['original_reference']);
    final requestId = row['original_request_id'] == null
        ? null
        : exceptionUuid(row['original_request_id']);
    if (reference != null &&
        (reference.exceptionId != exceptionId ||
            reference.requestId != requestId)) {
      exceptionInvalid();
    }
    final result = AdminExceptionFollowupQuarantine._(
      ownerDigest,
      exceptionId,
      reference,
      requestId,
    );
    if (result.encode() != encoded) {
      exceptionInvalid();
    }
    return result;
  }

  String encode() => jsonEncode({
    'version': 4,
    'owner_digest': ownerDigest,
    'exception_id': exceptionId,
    'original_reference': reference?.toJson(),
    'original_request_id': requestId,
  });
}

/// Immutable original action evidence. It does not establish current
/// assignment, recipient eligibility or delivery of an escalation.
class AdminExceptionFollowupReceipt {
  const AdminExceptionFollowupReceipt._(this.receipt, this.requestFingerprint);
  final AdminExceptionWorkflowReceipt receipt;
  final String requestFingerprint;
  String get requestId => receipt.requestId;
  String get exceptionId => receipt.exceptionId;
  String get action => receipt.action;
  int get sourceRevision => receipt.sourceRevision;
  int get revision => receipt.revision;
  String? get escalationId => receipt.escalationId;
  DateTime get recordedAt => receipt.recordedAt;

  factory AdminExceptionFollowupReceipt.parse(
    Object? raw,
    AdminExceptionFollowupReference reference,
  ) {
    final row = exceptionObject(raw, {
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
      'request_fingerprint',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        _digest(row['request_fingerprint']) != reference.requestFingerprint) {
      exceptionInvalid();
    }
    // Private identity-only validation reference for the existing receipt
    // parser. No fake assignee is added, and this never leaves this method or
    // becomes a full live intent/replay API.
    final validationReference = AdminExceptionWorkflowIntent(
      requestId: reference.requestId,
      exceptionId: reference.exceptionId,
      sourceRevision: reference.sourceRevision,
      workflowRevision: reference.workflowRevision,
      action: reference.action,
      expiresAt: reference.expiresAt,
    );
    final legacy = {...row}
      ..remove('request_fingerprint')
      ..['contract_version'] = 1;
    return AdminExceptionFollowupReceipt._(
      AdminExceptionWorkflowReceipt.parse(legacy, validationReference),
      reference.requestFingerprint,
    );
  }
}

class AdminExceptionFollowupLookup {
  const AdminExceptionFollowupLookup._({
    required this.reference,
    required this.status,
    required this.checkedAt,
    required this.validUntil,
    required this.receipt,
  });
  final AdminExceptionFollowupReference reference;
  final String status;
  final DateTime checkedAt, validUntil;
  final AdminExceptionFollowupReceipt? receipt;
  String get requestId => reference.requestId;
  String get requestFingerprint => reference.requestFingerprint;
  DateTime get expiresAt => reference.expiresAt;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  bool provesExpiredAbsence(DateTime now) =>
      status == 'not_recorded' &&
      isFresh(now) &&
      !checkedAt.isBefore(reference.expiresAt) &&
      !now.toUtc().isBefore(reference.expiresAt);

  factory AdminExceptionFollowupLookup.parse(
    Object? raw,
    AdminExceptionFollowupReference reference,
  ) {
    final row = exceptionObject(raw, {
      'contract_version',
      'request_id',
      'request_fingerprint',
      'expires_at',
      'checked_at',
      'sample_valid_until',
      'status',
      'receipt',
    });
    final sample = _sample(row), status = row['status'];
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        exceptionUuid(row['request_id']) != reference.requestId ||
        _digest(row['request_fingerprint']) != reference.requestFingerprint ||
        exceptionInstant(row['expires_at']) != reference.expiresAt ||
        status is! String ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(status) ||
        (status == 'recorded') != (row['receipt'] != null)) {
      exceptionInvalid();
    }
    final receipt = row['receipt'] == null
        ? null
        : AdminExceptionFollowupReceipt.parse(row['receipt'], reference);
    if (receipt?.recordedAt.isAfter(sample.checked) == true) {
      exceptionInvalid();
    }
    return AdminExceptionFollowupLookup._(
      reference: reference,
      status: status,
      checkedAt: sample.checked,
      validUntil: sample.until,
      receipt: receipt,
    );
  }
}

class AdminExceptionFollowupOperator {
  const AdminExceptionFollowupOperator._({
    required this.operatorId,
    required this.displayLabel,
    required this.createdAt,
  });
  final String operatorId, displayLabel;
  final DateTime createdAt;
  factory AdminExceptionFollowupOperator.parse(Object? raw) {
    final row = exceptionObject(raw, {
          'operator_id',
          'display_label',
          'created_at',
        }),
        label = row['display_label'];
    if (label is! String ||
        label.length != 17 ||
        !RegExp(r'^Collect ID [0-9]{6}$').hasMatch(label)) {
      exceptionInvalid();
    }
    return AdminExceptionFollowupOperator._(
      operatorId: exceptionUuid(row['operator_id']),
      displayLabel: label,
      createdAt: exceptionInstant(row['created_at']),
    );
  }
}

class AdminExceptionFollowupCursor {
  const AdminExceptionFollowupCursor({
    required this.createdAt,
    required this.operatorId,
  });
  final DateTime createdAt;
  final String operatorId;
  factory AdminExceptionFollowupCursor.parse(Object? raw) {
    final row = exceptionObject(raw, {'created_at', 'operator_id'});
    return AdminExceptionFollowupCursor(
      createdAt: exceptionInstant(row['created_at']),
      operatorId: exceptionUuid(row['operator_id']),
    );
  }
  Map<String, dynamic> toJson() => Map.unmodifiable({
    'created_at': _wire(createdAt),
    'operator_id': exceptionUuid(operatorId),
  });
  @override
  bool operator ==(Object other) =>
      other is AdminExceptionFollowupCursor &&
      createdAt == other.createdAt &&
      operatorId == other.operatorId;
  @override
  int get hashCode => Object.hash(createdAt, operatorId);
}

class AdminExceptionFollowupDirectoryQuery {
  const AdminExceptionFollowupDirectoryQuery({this.limit = 25, this.before});
  final int limit;
  final AdminExceptionFollowupCursor? before;
  Map<String, dynamic> get parameters {
    if (limit < 1 || limit > 25) {
      exceptionInvalid();
    }
    return Map.unmodifiable({
      'p_limit': limit,
      'p_before_created_at': before == null ? null : _wire(before!.createdAt),
      'p_before_operator_id': before == null
          ? null
          : exceptionUuid(before!.operatorId),
    });
  }

  @override
  bool operator ==(Object other) =>
      other is AdminExceptionFollowupDirectoryQuery &&
      limit == other.limit &&
      before == other.before;
  @override
  int get hashCode => Object.hash(limit, before);
}

int _order(DateTime leftAt, String leftId, DateTime rightAt, String rightId) {
  final time = leftAt.compareTo(rightAt);
  return time == 0 ? leftId.compareTo(rightId) : time;
}

class AdminExceptionFollowupDirectory {
  const AdminExceptionFollowupDirectory._({
    required this.limit,
    required this.checkedAt,
    required this.validUntil,
    required this.rows,
    required this.nextCursor,
  });
  final int limit;
  String get scope => 'platform_global';
  final DateTime checkedAt, validUntil;
  final List<AdminExceptionFollowupOperator> rows;
  final AdminExceptionFollowupCursor? nextCursor;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  bool isEligible(String operatorId, DateTime now) =>
      isFresh(now) && rows.any((row) => row.operatorId == operatorId);

  factory AdminExceptionFollowupDirectory.parse(
    Object? raw, {
    required AdminExceptionFollowupDirectoryQuery query,
  }) {
    query.parameters;
    final row = exceptionObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'limit',
      'rows',
      'next_cursor',
    });
    final sample = _sample(row), list = row['rows'];
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        row['scope'] != 'platform_global' ||
        row['limit'] is! int ||
        row['limit'] != query.limit ||
        list is! List ||
        list.length > query.limit) {
      exceptionInvalid();
    }
    final rows = list.map(AdminExceptionFollowupOperator.parse).toList();
    if (rows.map((item) => item.operatorId).toSet().length != rows.length ||
        rows.any((item) => item.createdAt.isAfter(sample.checked))) {
      exceptionInvalid();
    }
    AdminExceptionFollowupCursor? previous = query.before;
    for (final item in rows) {
      if (previous != null &&
          _order(
                item.createdAt,
                item.operatorId,
                previous.createdAt,
                previous.operatorId,
              ) >=
              0) {
        exceptionInvalid();
      }
      previous = AdminExceptionFollowupCursor(
        createdAt: item.createdAt,
        operatorId: item.operatorId,
      );
    }
    final next = row['next_cursor'] == null
        ? null
        : AdminExceptionFollowupCursor.parse(row['next_cursor']);
    if (next != null && (rows.length != query.limit || next != previous)) {
      exceptionInvalid();
    }
    return AdminExceptionFollowupDirectory._(
      limit: query.limit,
      checkedAt: sample.checked,
      validUntil: sample.until,
      rows: List.unmodifiable(rows),
      nextCursor: next,
    );
  }
}
