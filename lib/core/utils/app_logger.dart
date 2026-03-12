import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Structured logger for the Cool app.
///
/// Provides severity-leveled logging with tag prefixes and automatic
/// Crashlytics routing in release builds. Replaces scattered `debugPrint`.
///
/// ```dart
/// const _log = AppLogger('MomoService');
/// _log.info('Payment initiated for user $userId');
/// _log.error('Payment failed', error: e, stack: s);
/// ```
class AppLogger {
  const AppLogger(this.tag);

  /// Logical tag (usually the class or module name).
  final String tag;

  /// Debug-level: verbose info for local development only.
  /// Not sent to Crashlytics.
  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] 🐛 $message');
    }
  }

  /// Info-level: noteworthy runtime events.
  /// Logged as Crashlytics custom log in release.
  void info(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] ℹ️ $message');
    } else {
      _crashlyticsLog('[$tag] $message');
    }
  }

  /// Warning-level: unexpected but recoverable situations.
  /// Always logged to Crashlytics.
  void warn(String message, {Object? error}) {
    if (kDebugMode) {
      debugPrint('[$tag] ⚠️ $message${error != null ? ' — $error' : ''}');
    } else {
      _crashlyticsLog('[$tag] WARN: $message');
      if (error != null) {
        _crashlyticsRecordError(error, StackTrace.current, fatal: false);
      }
    }
  }

  /// Error-level: failures requiring attention.
  /// Always logged to Crashlytics as non-fatal.
  void error(String message, {Object? error, StackTrace? stack}) {
    if (kDebugMode) {
      debugPrint('[$tag] ❌ $message');
      if (error != null) debugPrint('  Error: $error');
      if (stack != null) debugPrint('  Stack: $stack');
    } else {
      _crashlyticsLog('[$tag] ERROR: $message');
      if (error != null) {
        _crashlyticsRecordError(
          error,
          stack ?? StackTrace.current,
          fatal: false,
        );
      }
    }
  }

  // ── Crashlytics helpers (silent if Firebase not initialized) ───────

  static void _crashlyticsLog(String message) {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.log(message);
      }
    } catch (_) {
      // Swallow — logging must never crash the app.
    }
  }

  static void _crashlyticsRecordError(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: fatal,
        );
      }
    } catch (_) {
      // Swallow.
    }
  }
}
