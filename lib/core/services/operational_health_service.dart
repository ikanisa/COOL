import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

const _log = AppLogger('OperationalHealth');

enum OperationalHealthStatus { ok, warn, error }

enum OperationalHealthSeverity { info, warning, critical }

class OperationalHealthService {
  OperationalHealthService({required SupabaseClient client}) : _client = client;

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
      final response = await _client.functions.invoke(
        'record-operational-health',
        body: <String, dynamic>{
          'service': service,
          'component': component,
          'status': status.name,
          'severity': (severity ?? _defaultSeverity(status)).name,
          'issueCode': _normalize(issueCode),
          'message': message,
          'functionName': _normalize(functionName),
          'userId': resolvedUserId,
          'subjectType': _normalize(subjectType),
          'subjectId': _normalize(subjectId),
          'metadata': metadata,
          'occurredAt': (occurredAt ?? DateTime.now().toUtc())
              .toIso8601String(),
        },
      );
      final data = response.data;
      if (data is Map && data['success'] == false) {
        throw StateError(
          data['message']?.toString() ??
              'Failed to record operational health event.',
        );
      }
    } catch (error) {
      _log.warn('Failed to record event: $error');
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
