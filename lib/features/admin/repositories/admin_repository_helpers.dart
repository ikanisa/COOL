import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared utility mixin for admin repositories providing common data helpers.
mixin AdminRepositoryHelpers {
  SupabaseClient get client;

  List<Map<String, dynamic>> asListOfMaps(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
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
