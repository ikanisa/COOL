import 'admin_gateway_contracts.dart';

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    gatewayInvalid();
  }
  return value;
}

String _choice(Object? value, Set<String> choices) {
  if (value is! String || !choices.contains(value)) {
    gatewayInvalid();
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) {
    gatewayInvalid();
  }
  return value;
}

bool _fresh(DateTime checked, DateTime until, DateTime now) =>
    !now.toUtc().isBefore(checked.subtract(const Duration(seconds: 5))) &&
    now.toUtc().isBefore(until);

void _sample(Map<String, dynamic> row, int limit) {
  if (row['contract_version'] is! int ||
      row['contract_version'] != 3 ||
      row['scope'] != 'rw_automatic_gateway_evidence' ||
      row['carrier_proof'] != false ||
      row['delivery_proven'] != false ||
      row['send_authority'] != false ||
      _integer(row['limit'], 1, 25) != limit ||
      gatewayInstant(row['sample_valid_until']) !=
          gatewayInstant(row['checked_at']).add(const Duration(seconds: 60))) {
    gatewayInvalid();
  }
}

int _compare(DateTime a, String aId, DateTime b, String bId) {
  final time = a.compareTo(b);
  return time == 0 ? aId.compareTo(bId) : time;
}

class AdminAutomaticAttempt {
  const AdminAutomaticAttempt._({
    required this.id,
    required this.receiptId,
    required this.deviceId,
    required this.runId,
    required this.principalId,
    required this.fence,
    required this.policyRevision,
    required this.segmentCount,
    required this.grantRequestId,
    required this.healthObservationId,
    required this.state,
    required this.issuedAt,
    required this.expiresAt,
    required this.updatedAt,
  });
  final String id,
      receiptId,
      deviceId,
      runId,
      principalId,
      grantRequestId,
      healthObservationId,
      state;
  final int fence, policyRevision, segmentCount;
  final DateTime issuedAt, expiresAt, updatedAt;
  factory AdminAutomaticAttempt.parse(Object? value, DateTime checkedAt) {
    final row = gatewayObject(value, {
      'attempt_id',
      'receipt_id',
      'device_id',
      'run_id',
      'principal_id',
      'fence_version',
      'policy_revision',
      'segment_count',
      'grant_request_id',
      'health_observation_id',
      'state',
      'issued_at',
      'expires_at',
      'updated_at',
    });
    final issued = gatewayInstant(row['issued_at']);
    final expires = gatewayInstant(row['expires_at']);
    final updated = gatewayInstant(row['updated_at']);
    if (issued.isAfter(checkedAt) ||
        updated.isBefore(issued) ||
        updated.isAfter(checkedAt) ||
        !expires.isAfter(issued) ||
        expires.isAfter(issued.add(const Duration(seconds: 30)))) {
      gatewayInvalid();
    }
    return AdminAutomaticAttempt._(
      id: gatewayUuid(row['attempt_id']),
      receiptId: gatewayUuid(row['receipt_id']),
      deviceId: gatewayUuid(row['device_id']),
      runId: gatewayUuid(row['run_id']),
      principalId: gatewayUuid(row['principal_id']),
      fence: _integer(row['fence_version'], 1, 1000000000),
      policyRevision: _integer(row['policy_revision'], 1, 1000000000),
      segmentCount: _integer(row['segment_count'], 1, 10),
      grantRequestId: gatewayUuid(row['grant_request_id']),
      healthObservationId: gatewayUuid(row['health_observation_id']),
      state: _choice(row['state'], {
        'granted',
        'send_started',
        'observed_sent',
        'uncertain',
      }),
      issuedAt: issued,
      expiresAt: expires,
      updatedAt: updated,
    );
  }
}

class AdminAutomaticArm {
  const AdminAutomaticArm._(
    this.requestId,
    this.healthObservationId,
    this.armedAt,
    this.expiresAt,
  );
  final String requestId, healthObservationId;
  final DateTime armedAt, expiresAt;
  factory AdminAutomaticArm.parse(
    Object? value,
    AdminAutomaticAttempt attempt,
    DateTime checkedAt,
  ) {
    final row = gatewayObject(value, {
      'request_id',
      'health_observation_id',
      'armed_at',
      'expires_at',
    });
    final armed = gatewayInstant(row['armed_at']);
    final expires = gatewayInstant(row['expires_at']);
    if (armed.isBefore(attempt.issuedAt) ||
        armed.isAfter(checkedAt) ||
        !expires.isAfter(armed) ||
        expires.isAfter(attempt.expiresAt) ||
        expires.isAfter(armed.add(const Duration(seconds: 30)))) {
      gatewayInvalid();
    }
    return AdminAutomaticArm._(
      gatewayUuid(row['request_id']),
      gatewayUuid(row['health_observation_id']),
      armed,
      expires,
    );
  }
}

class AdminAutomaticCallback {
  const AdminAutomaticCallback._(
    this.id,
    this.segmentIndex,
    this.kind,
    this.hasObservation,
    this.consistent,
    this.resultCode,
    this.tpStatus,
  );
  final String id, kind;
  final int segmentIndex;
  final bool hasObservation, consistent;
  final int? resultCode, tpStatus;
  factory AdminAutomaticCallback.parse(Object? value, int segments) {
    final row = gatewayObject(value, {
      'callback_id',
      'segment_index',
      'callback_kind',
      'has_observation',
      'consistent',
      'result_code',
      'tp_status',
    });
    final observed = _boolean(row['has_observation']);
    final consistent = _boolean(row['consistent']);
    final code = row['result_code'] == null
        ? null
        : _integer(row['result_code'], -1, 200);
    final tp = row['tp_status'] == null
        ? null
        : _integer(row['tp_status'], 0, 255);
    if (observed != (code != null) || !observed && (consistent || tp != null)) {
      gatewayInvalid();
    }
    return AdminAutomaticCallback._(
      gatewayUuid(row['callback_id']),
      _integer(row['segment_index'], 0, segments - 1),
      _choice(row['callback_kind'], {'sent', 'delivery'}),
      observed,
      consistent,
      code,
      tp,
    );
  }
}

class AdminAutomaticArchiveAck {
  const AdminAutomaticArchiveAck._(this.id, this.requestId, this.recordedAt);
  final String id, requestId;
  final DateTime recordedAt;
  factory AdminAutomaticArchiveAck.parse(
    Object? value,
    DateTime armedAt,
    DateTime checkedAt,
  ) {
    final row = gatewayObject(value, {
      'acknowledgement_id',
      'request_id',
      'recorded_at',
      'evidence_kind',
    });
    final at = gatewayInstant(row['recorded_at']);
    if (row['evidence_kind'] != 'complete_framework_callback_observations' ||
        at.isBefore(armedAt) ||
        at.isAfter(checkedAt)) {
      gatewayInvalid();
    }
    return AdminAutomaticArchiveAck._(
      gatewayUuid(row['acknowledgement_id']),
      gatewayUuid(row['request_id']),
      at,
    );
  }
}

class AdminAutomaticHistoryRow {
  const AdminAutomaticHistoryRow._(
    this.requestId,
    this.source,
    this.action,
    this.recordedAt,
    this.code,
    this.callbackId,
    this.segmentIndex,
    this.callbackKind,
    this.resultCode,
    this.tpStatus,
    this.occurredAt,
  );
  final String requestId, source, action;
  final String? code, callbackId, callbackKind;
  final int? segmentIndex, resultCode, tpStatus;
  final DateTime recordedAt;
  final DateTime? occurredAt;
  factory AdminAutomaticHistoryRow.parse(
    Object? value,
    DateTime checkedAt,
    List<AdminAutomaticCallback> bindings,
  ) {
    final row = gatewayObject(value, {
      'request_id',
      'source',
      'action',
      'recorded_at',
      'code',
      'callback_id',
      'segment_index',
      'callback_kind',
      'result_code',
      'tp_status',
      'occurred_at',
    });
    final source = _choice(row['source'], {
      'grant',
      'arm',
      'callback',
      'archive',
    });
    final action = switch (source) {
      'grant' => 'dispatch_grant',
      'arm' => 'arm_dispatch',
      'callback' => 'callback',
      _ => 'archive_attempt',
    };
    final at = gatewayInstant(row['recorded_at']);
    if (row['action'] != action || at.isAfter(checkedAt)) {
      gatewayInvalid();
    }
    String? callbackId, kind, code;
    int? segment, result, tp;
    DateTime? occurred;
    if (source == 'callback') {
      if (row['code'] != null) {
        gatewayInvalid();
      }
      callbackId = gatewayUuid(row['callback_id']);
      kind = _choice(row['callback_kind'], {'sent', 'delivery'});
      segment = _integer(row['segment_index'], 0, 9);
      result = _integer(row['result_code'], -1, 200);
      tp = row['tp_status'] == null ? null : _integer(row['tp_status'], 0, 255);
      occurred = gatewayInstant(row['occurred_at']);
      if (!bindings.any(
        (b) =>
            b.id == callbackId &&
            b.kind == kind &&
            b.segmentIndex == segment &&
            b.hasObservation,
      )) {
        gatewayInvalid();
      }
    } else {
      if ([
        'callback_id',
        'segment_index',
        'callback_kind',
        'result_code',
        'tp_status',
        'occurred_at',
      ].any((key) => row[key] != null)) {
        gatewayInvalid();
      }
      if (row['code'] != null) {
        final rawCode = row['code'];
        if (rawCode is! String ||
            !RegExp(r'^[A-Z][A-Z0-9_]{0,79}$').hasMatch(rawCode)) {
          gatewayInvalid();
        }
        code = rawCode;
      }
    }
    return AdminAutomaticHistoryRow._(
      gatewayUuid(row['request_id']),
      source,
      action,
      at,
      code,
      callbackId,
      segment,
      kind,
      result,
      tp,
      occurred,
    );
  }
}

class AdminAutomaticHistoryCursor {
  const AdminAutomaticHistoryCursor(this.recordedAt, this.requestId);
  final DateTime recordedAt;
  final String requestId;
  factory AdminAutomaticHistoryCursor.parse(Object? value) {
    final row = gatewayObject(value, {'recorded_at', 'request_id'});
    return AdminAutomaticHistoryCursor(
      gatewayInstant(row['recorded_at']),
      gatewayUuid(row['request_id']),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is AdminAutomaticHistoryCursor &&
      recordedAt == other.recordedAt &&
      requestId == other.requestId;
  @override
  int get hashCode => Object.hash(recordedAt, requestId);
}

class AdminAutomaticReceiptEvidence {
  const AdminAutomaticReceiptEvidence._(
    this.receiptId,
    this.status,
    this.checkedAt,
    this.validUntil,
    this.attempt,
    this.arm,
    this.expectedCallbacks,
    this.archiveAck,
    this.rows,
    this.nextCursor,
  );
  final String receiptId, status;
  final DateTime checkedAt, validUntil;
  final AdminAutomaticAttempt? attempt;
  final AdminAutomaticArm? arm;
  final List<AdminAutomaticCallback> expectedCallbacks;
  final AdminAutomaticArchiveAck? archiveAck;
  final List<AdminAutomaticHistoryRow> rows;
  final AdminAutomaticHistoryCursor? nextCursor;
  factory AdminAutomaticReceiptEvidence.parse(
    Object? value, {
    required String receiptId,
    int limit = 20,
    AdminAutomaticHistoryCursor? before,
  }) {
    gatewayUuid(receiptId);
    final row = gatewayObject(value, {
      'contract_version',
      'scope',
      'receipt_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'limit',
      'attempt',
      'arm',
      'expected_callbacks',
      'archive_ack',
      'history_complete',
      'rows',
      'next_cursor',
      'carrier_proof',
      'delivery_proven',
      'send_authority',
    });
    _sample(row, limit);
    if (row['receipt_id'] != receiptId ||
        row['history_complete'] != false ||
        row['rows'] is! List ||
        row['expected_callbacks'] is! List) {
      gatewayInvalid();
    }
    final checked = gatewayInstant(row['checked_at']);
    final status = _choice(row['status'], {
      'available',
      'no_automatic_attempt',
      'unavailable',
    });
    final attempt = row['attempt'] == null
        ? null
        : AdminAutomaticAttempt.parse(row['attempt'], checked);
    if ((status == 'available') != (attempt != null) ||
        attempt != null && attempt.receiptId != receiptId) {
      gatewayInvalid();
    }
    final arm = row['arm'] == null
        ? null
        : AdminAutomaticArm.parse(
            row['arm'],
            attempt ?? gatewayInvalid(),
            checked,
          );
    final rawBindings = row['expected_callbacks'] as List;
    if (rawBindings.length > 20 ||
        rawBindings.length != (arm == null ? 0 : attempt!.segmentCount * 2)) {
      gatewayInvalid();
    }
    final bindings = rawBindings
        .map((v) => AdminAutomaticCallback.parse(v, attempt!.segmentCount))
        .toList();
    if (bindings.map((b) => b.id).toSet().length != bindings.length ||
        bindings.map((b) => '${b.segmentIndex}:${b.kind}').toSet().length !=
            bindings.length) {
      gatewayInvalid();
    }
    final ack = row['archive_ack'] == null
        ? null
        : AdminAutomaticArchiveAck.parse(
            row['archive_ack'],
            arm?.armedAt ?? gatewayInvalid(),
            checked,
          );
    if (ack != null && bindings.any((b) => !b.hasObservation)) {
      gatewayInvalid();
    }
    final rawRows = row['rows'] as List;
    if (rawRows.length > limit) {
      gatewayInvalid();
    }
    final rows = rawRows
        .map((v) => AdminAutomaticHistoryRow.parse(v, checked, bindings))
        .toList();
    if (rows.map((r) => r.requestId).toSet().length != rows.length ||
        attempt == null && (arm != null || ack != null || rows.isNotEmpty)) {
      gatewayInvalid();
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (before != null &&
              _compare(
                    r.recordedAt,
                    r.requestId,
                    before.recordedAt,
                    before.requestId,
                  ) >=
                  0 ||
          i > 0 &&
              _compare(
                    rows[i - 1].recordedAt,
                    rows[i - 1].requestId,
                    r.recordedAt,
                    r.requestId,
                  ) <=
                  0 ||
          r.source == 'grant' && r.requestId != attempt!.grantRequestId ||
          r.source == 'arm' && r.requestId != arm?.requestId) {
        gatewayInvalid();
      }
    }
    final cursor = row['next_cursor'] == null
        ? null
        : AdminAutomaticHistoryCursor.parse(row['next_cursor']);
    if (cursor != null &&
        (rows.length != limit ||
            cursor.recordedAt != rows.last.recordedAt ||
            cursor.requestId != rows.last.requestId)) {
      gatewayInvalid();
    }
    return AdminAutomaticReceiptEvidence._(
      receiptId,
      status,
      checked,
      gatewayInstant(row['sample_valid_until']),
      attempt,
      arm,
      List.unmodifiable(bindings),
      ack,
      List.unmodifiable(rows),
      cursor,
    );
  }
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
}

class AdminAutomaticDeviceCursor {
  const AdminAutomaticDeviceCursor(this.issuedAt, this.attemptId);
  final DateTime issuedAt;
  final String attemptId;
  factory AdminAutomaticDeviceCursor.parse(Object? value) {
    final row = gatewayObject(value, {'issued_at', 'attempt_id'});
    return AdminAutomaticDeviceCursor(
      gatewayInstant(row['issued_at']),
      gatewayUuid(row['attempt_id']),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is AdminAutomaticDeviceCursor &&
      issuedAt == other.issuedAt &&
      attemptId == other.attemptId;
  @override
  int get hashCode => Object.hash(issuedAt, attemptId);
}

class AdminAutomaticDeviceEvidence {
  const AdminAutomaticDeviceEvidence._(
    this.deviceId,
    this.status,
    this.checkedAt,
    this.validUntil,
    this.scannedCount,
    this.rows,
    this.nextCursor,
  );
  final String deviceId, status;
  final DateTime checkedAt, validUntil;
  final int scannedCount;
  final List<AdminAutomaticAttempt> rows;
  final AdminAutomaticDeviceCursor? nextCursor;
  factory AdminAutomaticDeviceEvidence.parse(
    Object? value, {
    required String deviceId,
    int limit = 20,
    AdminAutomaticDeviceCursor? before,
  }) {
    gatewayUuid(deviceId);
    final row = gatewayObject(value, {
      'contract_version',
      'scope',
      'device_id',
      'status',
      'checked_at',
      'sample_valid_until',
      'limit',
      'scanned_count',
      'rows',
      'next_cursor',
      'carrier_proof',
      'delivery_proven',
      'send_authority',
    });
    _sample(row, limit);
    if (row['device_id'] != deviceId || row['rows'] is! List) {
      gatewayInvalid();
    }
    final checked = gatewayInstant(row['checked_at']);
    final status = _choice(row['status'], {'available', 'unavailable'});
    final count = _integer(row['scanned_count'], 0, limit);
    final raw = row['rows'] as List;
    if (raw.length > count) {
      gatewayInvalid();
    }
    final rows = raw
        .map((v) => AdminAutomaticAttempt.parse(v, checked))
        .toList();
    if (rows.map((a) => a.id).toSet().length != rows.length ||
        rows.map((a) => a.receiptId).toSet().length != rows.length) {
      gatewayInvalid();
    }
    for (var i = 0; i < rows.length; i++) {
      final a = rows[i];
      if (a.deviceId != deviceId ||
          before != null &&
              _compare(a.issuedAt, a.id, before.issuedAt, before.attemptId) >=
                  0 ||
          i > 0 &&
              _compare(
                    rows[i - 1].issuedAt,
                    rows[i - 1].id,
                    a.issuedAt,
                    a.id,
                  ) <=
                  0) {
        gatewayInvalid();
      }
    }
    final cursor = row['next_cursor'] == null
        ? null
        : AdminAutomaticDeviceCursor.parse(row['next_cursor']);
    // The cursor names the last scanned row. Current Rwanda filtering may hide
    // that row, or the entire page. Continuation never depends on visible rows.
    if (cursor != null &&
        (count != limit ||
            cursor.issuedAt.isAfter(checked) ||
            before != null &&
                _compare(
                      cursor.issuedAt,
                      cursor.attemptId,
                      before.issuedAt,
                      before.attemptId,
                    ) >=
                    0 ||
            rows.isNotEmpty &&
                _compare(
                      cursor.issuedAt,
                      cursor.attemptId,
                      rows.last.issuedAt,
                      rows.last.id,
                    ) >
                    0 ||
            rows.length == count &&
                (cursor.issuedAt != rows.last.issuedAt ||
                    cursor.attemptId != rows.last.id))) {
      gatewayInvalid();
    }
    if (status == 'unavailable' &&
        (count != 0 || rows.isNotEmpty || cursor != null)) {
      gatewayInvalid();
    }
    return AdminAutomaticDeviceEvidence._(
      deviceId,
      status,
      checked,
      gatewayInstant(row['sample_valid_until']),
      count,
      List.unmodifiable(rows),
      cursor,
    );
  }
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
}
