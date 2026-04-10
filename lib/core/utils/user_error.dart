import 'dart:async';
import 'dart:io';

/// Converts an error object into a user-facing message.
///
/// Strips Dart type prefixes, maps known exceptions to plain language,
/// and truncates long messages. Use this instead of `error.toString()`.
String describeUserFacingError(Object error) {
  if (error is TimeoutException) {
    return 'The request timed out. Check your network and try again.';
  }

  if (error is SocketException || error is HandshakeException) {
    return 'Could not connect to the server. Check your internet connection.';
  }

  final raw = error.toString();

  // Supabase Postgrest errors
  if (raw.contains('PostgrestException')) {
    if (raw.contains('duplicate key')) {
      return 'This record already exists.';
    }
    if (raw.contains('violates foreign key')) {
      return 'A required reference was not found.';
    }
    if (raw.contains('permission denied') || raw.contains('RLS')) {
      return 'You do not have permission to perform this action.';
    }
    // Generic Postgrest fallback
    final messageMatch = RegExp(r'message:\s*(.+?)(?:,|\))').firstMatch(raw);
    if (messageMatch != null) {
      return messageMatch.group(1)?.trim() ?? _sanitize(raw);
    }
  }

  // Network / timeout patterns
  if (raw.contains('SocketException') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection reset')) {
    return 'Could not connect to the server. Check your internet connection.';
  }
  if (raw.contains('TimeoutException') || raw.contains('timed out')) {
    return 'The request timed out. Check your network and try again.';
  }
  if (raw.contains('HandshakeException') || raw.contains('CERTIFICATE_')) {
    return 'A secure connection could not be established.';
  }

  // Dart built-in error prefixes
  if (raw.startsWith('StateError: ')) {
    return raw.substring('StateError: '.length);
  }
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  if (raw.startsWith('FormatException: ')) {
    return raw.substring('FormatException: '.length);
  }
  if (raw.startsWith('RangeError: ')) {
    return 'An unexpected value was encountered. Please try again.';
  }

  return _sanitize(raw);
}

String _sanitize(String raw) {
  // Truncate overly long error messages
  if (raw.length > 200) {
    return '${raw.substring(0, 197)}...';
  }
  return raw;
}
