import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/supabase_query_helpers.dart' as sq;

/// Shared utility mixin for admin repositories providing common data helpers.
mixin AdminRepositoryHelpers {
  SupabaseClient get client;

  Duration get rpcTimeout => sq.kSupabaseRpcTimeout;

  Future<T> guarded<T>(
    Future<T> Function() query, {
    Duration timeout = sq.kSupabaseQueryTimeout,
    String? label,
  }) {
    return sq.guarded(query, timeout: timeout, label: label);
  }

  List<Map<String, dynamic>> asListOfMaps(dynamic value) {
    return sq.asListOfMaps(value);
  }

  Map<String, dynamic> asMap(dynamic value) {
    return sq.asMap(value);
  }

  String? trimmed(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  int asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool isMissingSchemaObjectError(PostgrestException error) {
    final normalizedMessage = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        error.code == 'PGRST205' ||
        normalizedMessage.contains('does not exist') ||
        normalizedMessage.contains('could not find') ||
        normalizedMessage.contains('missing table') ||
        normalizedMessage.contains('missing function');
  }
}
