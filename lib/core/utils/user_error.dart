import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// Converts an error object into a user-facing message.
///
/// Strips Dart type prefixes, maps known exceptions to plain language,
/// and truncates long messages. Use this instead of `error.toString()`.
String describeUserFacingError(Object error) {
  if (error is TimeoutException) {
    return 'The request timed out. Check your network and try again.';
  }

  if (error is AuthException) {
    return _describeAuthError(error);
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

String _describeAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  final code = error.statusCode?.toLowerCase() ?? '';

  // Rate limiting
  if (message.contains('rate limit') || code == '429') {
    return 'Too many attempts. Please wait a moment and try again.';
  }

  // Invalid credentials / login
  if (message.contains('invalid login') ||
      message.contains('invalid_credentials') ||
      message.contains('invalid email or password')) {
    return 'Invalid credentials. Please check and try again.';
  }

  // User not found
  if (message.contains('user not found') ||
      message.contains('user_not_found')) {
    return 'No account found with these details.';
  }

  // OTP issues
  if (message.contains('otp_expired') || message.contains('token has expired')) {
    return 'Your verification code has expired. Please request a new one.';
  }
  if (message.contains('otp_disabled')) {
    return 'Verification is temporarily unavailable. Please try again later.';
  }

  // Session issues
  if (message.contains('session_not_found') ||
      message.contains('session_expired') ||
      message.contains('refresh_token')) {
    return 'Your session has expired. Please sign in again.';
  }

  // Email not confirmed
  if (message.contains('email_not_confirmed') ||
      message.contains('not confirmed')) {
    return 'Please verify your email address before signing in.';
  }

  // Phone not confirmed
  if (message.contains('phone_not_confirmed')) {
    return 'Please verify your phone number before signing in.';
  }

  // Generic auth fallback
  final cleaned = error.message.trim();
  if (cleaned.isNotEmpty && cleaned.length <= 200) {
    return cleaned;
  }
  return 'Authentication failed. Please try again.';
}

String _sanitize(String raw) {
  // Truncate overly long error messages
  if (raw.length > 200) {
    return '${raw.substring(0, 197)}...';
  }
  return raw;
}
