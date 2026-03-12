/// Centralized network-error detection.
///
/// Replaces the scattered `_shouldStoreOffline` pattern found in
/// `trip_repository.dart` and similar files.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns `true` when [error] is a transient network failure that should
/// trigger offline fallback rather than a permanent application error.
///
/// Network errors are retryable. Postgrest errors (e.g. constraint violations,
/// auth failures) are NOT retryable and should propagate immediately.
bool isNetworkError(Object error) {
  // Explicit timeout from Dart's async library.
  if (error is TimeoutException) {
    return true;
  }

  // Postgrest errors are server-side — they are NOT network errors.
  if (error is PostgrestException) {
    return false;
  }

  // Heuristic: match common connectivity error messages.
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('timed out') ||
      message.contains('xmlhttprequest error') ||
      message.contains('clientexception');
}
