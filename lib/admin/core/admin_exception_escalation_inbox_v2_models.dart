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

class AdminExceptionEscalationInboxCursor {
  const AdminExceptionEscalationInboxCursor({
    required this.deliveredAt,
    required this.escalationId,
  });
  final DateTime deliveredAt;
  final String escalationId;
  int compareTo(AdminExceptionEscalationInboxCursor other) {
    final time = deliveredAt.toUtc().compareTo(other.deliveredAt.toUtc());
    return time == 0 ? escalationId.compareTo(other.escalationId) : time;
  }

  factory AdminExceptionEscalationInboxCursor.parse(Object? raw) {
    final row = exceptionObject(raw, {'delivered_at', 'escalation_id'});
    return AdminExceptionEscalationInboxCursor(
      deliveredAt: exceptionInstant(row['delivered_at']),
      escalationId: exceptionUuid(row['escalation_id']),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is AdminExceptionEscalationInboxCursor &&
      deliveredAt == other.deliveredAt &&
      escalationId == other.escalationId;
  @override
  int get hashCode => Object.hash(deliveredAt, escalationId);
}

class AdminExceptionEscalationInboxQuery {
  const AdminExceptionEscalationInboxQuery({this.limit = 20, this.before});
  final int limit;
  final AdminExceptionEscalationInboxCursor? before;
  void validate() {
    if (limit < 1 || limit > 25) {
      exceptionInvalid();
    }
    if (before != null) {
      _wire(before!.deliveredAt);
      exceptionUuid(before!.escalationId);
    }
  }

  Map<String, dynamic> get parameters {
    validate();
    return Map.unmodifiable({
      'p_limit': limit,
      'p_before_delivered_at': before == null
          ? null
          : _wire(before!.deliveredAt),
      'p_before_escalation_id': before?.escalationId,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is AdminExceptionEscalationInboxQuery &&
      limit == other.limit &&
      before == other.before;
  @override
  int get hashCode => Object.hash(limit, before);
}

class AdminExceptionEscalationInboxSnapshot {
  const AdminExceptionEscalationInboxSnapshot._({
    required this.query,
    required this.recipientId,
    required this.checkedAt,
    required this.validUntil,
    required this.rows,
    required this.nextCursor,
  });
  final AdminExceptionEscalationInboxQuery query;
  final String recipientId;
  final DateTime checkedAt, validUntil;
  final List<AdminExceptionInboxDelivery> rows;
  final AdminExceptionEscalationInboxCursor? nextCursor;
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
  factory AdminExceptionEscalationInboxSnapshot.parse(
    Object? raw, {
    required AdminExceptionEscalationInboxQuery query,
    required String recipientId,
  }) {
    query.validate();
    exceptionUuid(recipientId);
    final row = exceptionObject(raw, {
      'contract_version',
      'channel',
      'scope',
      'recipient_id',
      'checked_at',
      'sample_valid_until',
      'limit',
      'rows',
      'next_cursor',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        row['channel'] != 'admin_inbox' ||
        row['scope'] != 'current_operator' ||
        row['recipient_id'] != recipientId ||
        row['limit'] is! int ||
        row['limit'] != query.limit) {
      exceptionInvalid();
    }
    final checked = exceptionInstant(row['checked_at']),
        until = exceptionInstant(row['sample_valid_until']);
    final values = row['rows'];
    if (until.difference(checked) != const Duration(seconds: 60) ||
        values is! List ||
        values.length > query.limit) {
      exceptionInvalid();
    }
    final rows = values
        .map((value) => AdminExceptionInboxDelivery.parse(value, checked))
        .toList();
    final ids = <String>{};
    AdminExceptionEscalationInboxCursor? previous = query.before;
    for (final value in rows) {
      final cursor = AdminExceptionEscalationInboxCursor(
        deliveredAt: value.deliveredAt,
        escalationId: value.id,
      );
      if (!ids.add(value.id) ||
          previous != null && cursor.compareTo(previous) >= 0) {
        exceptionInvalid();
      }
      previous = cursor;
    }
    final next = row['next_cursor'] == null
        ? null
        : AdminExceptionEscalationInboxCursor.parse(row['next_cursor']);
    if (next != null && (rows.length != query.limit || next != previous)) {
      exceptionInvalid();
    }
    return AdminExceptionEscalationInboxSnapshot._(
      query: query,
      recipientId: recipientId,
      checkedAt: checked,
      validUntil: until,
      rows: List.unmodifiable(rows),
      nextCursor: next,
    );
  }
}

/// Idempotent opening evidence under current authority; no source resolution,
/// financial handling or delivery acknowledgement is implied by this receipt.
class AdminExceptionEscalationReadReceipt {
  const AdminExceptionEscalationReadReceipt._(this.escalationId, this.readAt);
  final String escalationId;
  final DateTime readAt;
  factory AdminExceptionEscalationReadReceipt.parse(
    Object? raw, {
    required String escalationId,
    DateTime? deliveredAt,
  }) {
    exceptionUuid(escalationId);
    final row = exceptionObject(raw, {
      'contract_version',
      'escalation_id',
      'read_at',
      'source_resolved',
    });
    final read = exceptionInstant(row['read_at']);
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        row['escalation_id'] != escalationId ||
        row['source_resolved'] != false ||
        deliveredAt != null && read.isBefore(deliveredAt)) {
      exceptionInvalid();
    }
    return AdminExceptionEscalationReadReceipt._(escalationId, read);
  }
}
