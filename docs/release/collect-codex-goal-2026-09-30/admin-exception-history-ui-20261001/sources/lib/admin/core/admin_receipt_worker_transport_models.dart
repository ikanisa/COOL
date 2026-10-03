import 'admin_exception_models.dart';

/// Captured HTTP evidence and the separate immutable original worker result.
/// HTTP acceptance never establishes source processing or message delivery.
class AdminReceiptWorkerTransport {
  const AdminReceiptWorkerTransport._({
    required this.requestId,
    required this.checkedAt,
    required this.validUntil,
    required this.originalStatus,
    required this.originalExpiresAt,
    required this.originalReceiptStatus,
    required this.scanRequestId,
    required this.rows,
    required this.alerts,
    required this.collector,
  });

  final String requestId, originalStatus;
  final DateTime checkedAt, validUntil, originalExpiresAt;
  final String? originalReceiptStatus, scanRequestId;
  final List<AdminReceiptWorkerTransportAttempt> rows;
  final List<String> alerts;
  final AdminReceiptWorkerTransportCollector collector;

  static const statusLabels = <String, String>{
    'recorded': 'Original worker receipt recorded',
    'pending': 'Original worker receipt pending',
    'in_progress': 'Original worker reconciliation in progress',
    'unknown': 'Original worker outcome unknown',
    'expired_without_receipt': 'Original expired without a worker receipt',
  };
  static const alertLabels = <String, String>{
    ...AdminReceiptWorkerTransportAttempt.outcomeLabels,
    'COLLECTOR_UNOBSERVED': 'No transport collection observed',
    'COLLECTOR_STALE': 'Transport collection is overdue',
    'COLLECTOR_QUOTA_EXHAUSTED': 'Transport inspection budget exhausted',
    'SOURCE_SCHEMA_UNAVAILABLE': 'Transport response source unavailable',
  };

  String get originalStatusLabel => statusLabels[originalStatus]!;
  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);

  factory AdminReceiptWorkerTransport.parse(
    Object? raw, {
    required String requestId,
    required DateTime expectedExpiresAt,
  }) {
    final data = exceptionObject(raw, {
      'contract_version',
      'request_id',
      'checked_at',
      'sample_valid_until',
      'original_status',
      'original_expires_at',
      'original_receipt_status',
      'scan_request_id',
      'rows',
      'alerts',
      'collector',
      'source_scan_complete',
      'financial_action',
      'send_action',
      'resend_action',
    });
    final checked = exceptionInstant(data['checked_at']);
    final until = exceptionInstant(data['sample_valid_until']);
    final expires = exceptionInstant(data['original_expires_at']);
    final original = exceptionUuid(data['request_id']);
    final status = data['original_status'];
    final receipt = data['original_receipt_status'];
    final scan = data['scan_request_id'] == null
        ? null
        : exceptionUuid(data['scan_request_id']);
    final rawRows = data['rows'];
    final rawAlerts = data['alerts'];
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        original != exceptionUuid(requestId) ||
        expires != expectedExpiresAt.toUtc() ||
        until.difference(checked) != const Duration(seconds: 60) ||
        status is! String ||
        !statusLabels.containsKey(status) ||
        (status == 'recorded') != (receipt != null) ||
        (status == 'recorded') != (scan != null) ||
        scan != null && scan != original ||
        receipt != null && !{'completed', 'busy'}.contains(receipt) ||
        status == 'pending' && !expires.isAfter(checked) ||
        {'unknown', 'expired_without_receipt'}.contains(status) &&
            expires.isAfter(checked) ||
        data['source_scan_complete'] != false ||
        data['financial_action'] != false ||
        data['send_action'] != false ||
        data['resend_action'] != false ||
        rawRows is! List ||
        rawRows.length > 3 ||
        rawAlerts is! List ||
        rawAlerts.length > alertLabels.length ||
        rawAlerts.any(
          (value) =>
              value is! String ||
              !alertLabels.containsKey(value) ||
              {'HTTP_ACCEPTED', 'HTTP_PENDING'}.contains(value),
        ) ||
        rawAlerts.toSet().length != rawAlerts.length) {
      exceptionInvalid();
    }
    final rows = rawRows
        .map(
          (value) => AdminReceiptWorkerTransportAttempt._parse(value, checked),
        )
        .toList();
    final ids = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row.attempt != index + 1 ||
          !ids.add(row.httpRequestId) ||
          row.dispatchedAt.isBefore(
            expires.subtract(const Duration(seconds: 90)),
          ) ||
          row.dispatchedAt.isAfter(expires) ||
          index > 0 &&
              row.dispatchedAt.difference(rows[index - 1].dispatchedAt) <
                  const Duration(seconds: 30)) {
        exceptionInvalid();
      }
    }
    final collector = AdminReceiptWorkerTransportCollector._parse(
      data['collector'],
      checked,
    );
    final requiredAlerts = <String>{
      if (rows.isNotEmpty &&
          !{'HTTP_ACCEPTED', 'HTTP_PENDING'}.contains(rows.last.outcome))
        rows.last.outcome,
      if (collector.lastRecordedAt == null) 'COLLECTOR_UNOBSERVED',
      if (collector.lastRecordedAt?.isBefore(
            checked.subtract(const Duration(seconds: 180)),
          ) ==
          true)
        'COLLECTOR_STALE',
      if (collector.quotaExhausted) 'COLLECTOR_QUOTA_EXHAUSTED',
      if (!collector.sourceSchemaValid) 'SOURCE_SCHEMA_UNAVAILABLE',
    };
    if (rawAlerts.length != requiredAlerts.length ||
        !rawAlerts.toSet().containsAll(requiredAlerts)) {
      exceptionInvalid();
    }
    return AdminReceiptWorkerTransport._(
      requestId: original,
      checkedAt: checked,
      validUntil: until,
      originalStatus: status,
      originalExpiresAt: expires,
      originalReceiptStatus: receipt as String?,
      scanRequestId: scan,
      rows: List.unmodifiable(rows),
      alerts: List.unmodifiable(rawAlerts.cast<String>()),
      collector: collector,
    );
  }
}

class AdminReceiptWorkerTransportAttempt {
  const AdminReceiptWorkerTransportAttempt._({
    required this.attempt,
    required this.httpRequestId,
    required this.dispatchedAt,
    required this.evidenceRevision,
    required this.outcome,
    required this.transportTerminal,
    required this.httpStatus,
    required this.workerErrorCode,
    required this.responseRowsObserved,
    required this.responseAt,
    required this.observedAt,
    required this.evidenceSha256,
  });
  final int attempt;
  final String httpRequestId, outcome;
  final DateTime dispatchedAt;
  final int? evidenceRevision, httpStatus, responseRowsObserved;
  final String? workerErrorCode, evidenceSha256;
  final DateTime? responseAt, observedAt;
  final bool transportTerminal;

  static const outcomeLabels = <String, String>{
    'NOT_COLLECTED': 'HTTP evidence not collected',
    'QUEUED_UNOBSERVED': 'HTTP request queued; response unobserved',
    'RESPONSE_UNOBSERVED': 'HTTP response unobserved',
    'HTTP_ACCEPTED': 'HTTP accepted; check original worker receipt',
    'HTTP_PENDING': 'HTTP pending; check original worker receipt',
    'AUTH_REFUSED': 'Worker authentication refused',
    'ENDPOINT_UNAVAILABLE': 'Worker endpoint unavailable',
    'REQUEST_REFUSED': 'Worker request refused',
    'ORIGINAL_CONFLICT': 'Original worker request conflict',
    'WORKER_CONFIG_REFUSED': 'Worker configuration refused',
    'RATE_LIMITED': 'Worker HTTP rate limit reached',
    'HTTP_SERVER_FAILURE': 'Worker HTTP server failure',
    'HTTP_REFUSED': 'Worker HTTP request rejected',
    'HTTP_UNEXPECTED': 'Unexpected worker HTTP response',
    'NETWORK_TIMEOUT': 'Worker network timeout',
    'NETWORK_FAILURE': 'Worker network failure',
    'RESPONSE_INVALID': 'Invalid worker response metadata',
    'RESPONSE_CONFLICT': 'Conflicting worker response rows',
  };
  static const workerErrors = <String>{
    'WORKER_UNCONFIGURED',
    'WORKER_AUTH_REQUIRED',
    'WORKER_REQUEST_INVALID',
    'WORKER_AUTHORITY_REFUSED',
    'WORKER_ORIGINAL_CONFLICT',
    'WORKER_LOOKUP_UNAVAILABLE',
    'WORKER_OUTCOME_UNKNOWN',
    'METHOD_NOT_ALLOWED',
  };
  String get outcomeLabel => outcomeLabels[outcome]!;

  static AdminReceiptWorkerTransportAttempt _parse(
    Object? raw,
    DateTime checked,
  ) {
    final data = exceptionObject(raw, {
      'attempt',
      'http_request_id',
      'dispatched_at',
      'evidence_revision',
      'outcome',
      'transport_terminal',
      'http_status',
      'worker_error_code',
      'response_rows_observed',
      'response_at',
      'observed_at',
      'evidence_sha256',
    });
    final attempt = _integer(data['attempt'], 1, 3);
    final id = data['http_request_id'];
    final dispatched = exceptionInstant(data['dispatched_at']);
    final outcome = data['outcome'];
    final terminal = data['transport_terminal'];
    final revision = _nullableInteger(data['evidence_revision'], 1, 1000000000);
    final status = _nullableInteger(data['http_status'], 100, 599);
    final count = _nullableInteger(data['response_rows_observed'], 0, 2);
    final response = data['response_at'] == null
        ? null
        : exceptionInstant(data['response_at']);
    final observed = data['observed_at'] == null
        ? null
        : exceptionInstant(data['observed_at']);
    final hash = data['evidence_sha256'];
    final error = data['worker_error_code'];
    if (id is! String ||
        !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) ||
        BigInt.parse(id) > BigInt.parse('9223372036854775807') ||
        outcome is! String ||
        !outcomeLabels.containsKey(outcome) ||
        terminal is! bool ||
        dispatched.isAfter(checked.add(const Duration(seconds: 5))) ||
        error != null && !workerErrors.contains(error) ||
        observed?.isAfter(checked.add(const Duration(seconds: 5))) == true ||
        observed != null && observed.isBefore(dispatched) ||
        response != null && (observed == null || response.isAfter(observed)) ||
        (revision == null) != (outcome == 'NOT_COLLECTED') ||
        (revision == null) != (observed == null) ||
        (revision == null) != (count == null) ||
        (revision == null) != (hash == null) ||
        hash != null &&
            (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) ||
        terminal !=
            !{
              'NOT_COLLECTED',
              'QUEUED_UNOBSERVED',
              'RESPONSE_UNOBSERVED',
            }.contains(outcome)) {
      exceptionInvalid();
    }
    if (outcome == 'NOT_COLLECTED' &&
            (status != null || error != null || response != null) ||
        {'QUEUED_UNOBSERVED', 'RESPONSE_UNOBSERVED'}.contains(outcome) &&
            (count != 0 ||
                status != null ||
                error != null ||
                response != null) ||
        outcome == 'RESPONSE_CONFLICT' &&
            (count != 2 ||
                status != null ||
                error != null ||
                response != null) ||
        terminal && outcome != 'RESPONSE_CONFLICT' && count != 1 ||
        {'NETWORK_TIMEOUT', 'NETWORK_FAILURE'}.contains(outcome) &&
            (status != null || error != null || response == null) ||
        outcome != 'RESPONSE_INVALID' &&
            terminal &&
            outcome != 'RESPONSE_CONFLICT' &&
            response == null ||
        outcome == 'HTTP_ACCEPTED' &&
            (status == null || status < 200 || status > 299 || status == 202) ||
        outcome == 'HTTP_PENDING' && status != 202 ||
        outcome == 'AUTH_REFUSED' && !{401, 403}.contains(status) ||
        outcome == 'ENDPOINT_UNAVAILABLE' && !{404, 405}.contains(status) ||
        outcome == 'REQUEST_REFUSED' &&
            !{400, 409, 413, 415, 422}.contains(status) ||
        outcome == 'ORIGINAL_CONFLICT' &&
            (status != 409 || error != 'WORKER_ORIGINAL_CONFLICT') ||
        outcome == 'WORKER_CONFIG_REFUSED' &&
            (status != 503 || error != 'WORKER_UNCONFIGURED') ||
        outcome == 'RATE_LIMITED' && status != 429 ||
        outcome == 'HTTP_SERVER_FAILURE' &&
            (status == null || status < 500 || status > 599) ||
        outcome == 'HTTP_REFUSED' &&
            (status == null ||
                status < 400 ||
                status > 499 ||
                {
                  400,
                  401,
                  403,
                  404,
                  405,
                  409,
                  413,
                  415,
                  422,
                  429,
                }.contains(status)) ||
        outcome == 'HTTP_UNEXPECTED' &&
            (status == null ||
                status >= 200 && status < 300 ||
                status >= 400) ||
        outcome == 'RESPONSE_INVALID' && error != null) {
      exceptionInvalid();
    }
    return AdminReceiptWorkerTransportAttempt._(
      attempt: attempt,
      httpRequestId: id,
      dispatchedAt: dispatched,
      evidenceRevision: revision,
      outcome: outcome,
      transportTerminal: terminal,
      httpStatus: status,
      workerErrorCode: error as String?,
      responseRowsObserved: count,
      responseAt: response,
      observedAt: observed,
      evidenceSha256: hash as String?,
    );
  }
}

class AdminReceiptWorkerTransportCollector {
  const AdminReceiptWorkerTransportCollector._({
    required this.revision,
    required this.lastRequestId,
    required this.lastRecordedAt,
    required this.dayInspections,
    required this.dayCap,
    required this.quotaExhausted,
    required this.sourceSchemaValid,
  });
  final int revision, dayInspections, dayCap;
  final String? lastRequestId;
  final DateTime? lastRecordedAt;
  final bool quotaExhausted, sourceSchemaValid;

  static AdminReceiptWorkerTransportCollector _parse(
    Object? raw,
    DateTime checked,
  ) {
    final data = exceptionObject(raw, {
      'configuration_revision',
      'last_request_id',
      'last_recorded_at',
      'day_inspections',
      'day_cap',
      'quota_exhausted',
      'source_schema_valid',
    });
    final request = data['last_request_id'] == null
        ? null
        : exceptionUuid(data['last_request_id']);
    final recorded = data['last_recorded_at'] == null
        ? null
        : exceptionInstant(data['last_recorded_at']);
    final units = _integer(data['day_inspections'], 0, 1000000000);
    final cap = _integer(data['day_cap'], 1, 72000);
    if ((request == null) != (recorded == null) ||
        recorded?.isAfter(checked.add(const Duration(seconds: 5))) == true ||
        data['quota_exhausted'] is! bool ||
        data['quota_exhausted'] != (units >= cap) ||
        data['source_schema_valid'] is! bool) {
      exceptionInvalid();
    }
    return AdminReceiptWorkerTransportCollector._(
      revision: _integer(data['configuration_revision'], 1, 1000000000),
      lastRequestId: request,
      lastRecordedAt: recorded,
      dayInspections: units,
      dayCap: cap,
      quotaExhausted: data['quota_exhausted'] as bool,
      sourceSchemaValid: data['source_schema_valid'] as bool,
    );
  }
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) exceptionInvalid();
  return value;
}

int? _nullableInteger(Object? value, int minimum, int maximum) =>
    value == null ? null : _integer(value, minimum, maximum);
