import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OperationalHealthStatus { ok, warn, error }

enum OperationalHealthSeverity { info, warning, critical }

class OperationalHealthService {
  OperationalHealthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static final OperationalHealthService instance = OperationalHealthService();

  final SupabaseClient _client;

  Future<void> recordEvent({
    required String service,
    required String component,
    required String message,
    OperationalHealthStatus status = OperationalHealthStatus.ok,
    OperationalHealthSeverity? severity,
    String? issueCode,
    String? functionName,
    String? userId,
    String? subjectType,
    String? subjectId,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    DateTime? occurredAt,
  }) async {
    final resolvedUserId = _normalize(userId) ?? _client.auth.currentUser?.id;

    try {
      await _client.from('operational_health_events').insert(<String, dynamic>{
        'service': service,
        'component': component,
        'status': status.name,
        'severity': (severity ?? _defaultSeverity(status)).name,
        'issue_code': _normalize(issueCode),
        'message': message,
        'function_name': _normalize(functionName),
        'user_id': resolvedUserId,
        'subject_type': _normalize(subjectType),
        'subject_id': _normalize(subjectId),
        'metadata': metadata,
        'occurred_at': (occurredAt ?? DateTime.now().toUtc()).toIso8601String(),
      });
    } catch (error) {
      debugPrint('[OperationalHealth] Failed to record event: $error');
    }
  }

  OperationalHealthSeverity _defaultSeverity(OperationalHealthStatus status) {
    switch (status) {
      case OperationalHealthStatus.warn:
        return OperationalHealthSeverity.warning;
      case OperationalHealthStatus.error:
        return OperationalHealthSeverity.critical;
      case OperationalHealthStatus.ok:
        return OperationalHealthSeverity.info;
    }
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
