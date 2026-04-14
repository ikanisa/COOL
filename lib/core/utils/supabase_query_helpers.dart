/// Shared helpers for Supabase query execution safety.
///
/// Provides timeout guards, consistent data coercion, and input
/// sanitization for all repositories that talk to Supabase.
library;

import 'dart:async';

/// Default timeout for standard Supabase queries (select, insert, update).
const Duration kSupabaseQueryTimeout = Duration(seconds: 15);

/// Timeout for heavier operations (RPCs, multi-step atomic writes).
const Duration kSupabaseRpcTimeout = Duration(seconds: 20);

/// Executes a Supabase query with a timeout guard.
///
/// Wraps any `Future` returned by the Supabase client so that a hung
/// network request does not block the UI indefinitely.
///
/// ```dart
/// final rows = await guarded(() => _client.from('groups').select());
/// ```
Future<T> guarded<T>(
  Future<T> Function() query, {
  Duration timeout = kSupabaseQueryTimeout,
  String? label,
}) {
  return query().timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      label != null
          ? '$label timed out after ${timeout.inSeconds}s. '
              'Check your network and try again.'
          : 'Request timed out after ${timeout.inSeconds}s. '
              'Check your network and try again.',
      timeout,
    ),
  );
}

/// Coerces a Supabase response to a `List<Map<String, dynamic>>`.
///
/// Returns an empty list if [value] is not a list. Each entry is
/// cast from `Map<dynamic, dynamic>` to `Map<String, dynamic>`.
List<Map<String, dynamic>> asListOfMaps(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .whereType<Map<dynamic, dynamic>>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

/// Coerces a Supabase response to a `Map<String, dynamic>`.
///
/// Returns an empty map if [value] is not a map.
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

/// Returns [value] trimmed, or `null` when blank/empty.
String? trimToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Escapes characters that have special meaning in Supabase `ilike` filters.
String escapeLike(String value) {
  return value.replaceAll('%', r'\%').replaceAll(',', r'\,');
}
