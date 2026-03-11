import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wraps [FirebaseCrashlytics] with graceful degradation and user identity.
///
/// Call [initialize] once after Firebase is ready. All public methods
/// silently no-op when Crashlytics is unavailable (e.g. iOS simulator,
/// Firebase init failed).
class CrashlyticsService {
  FirebaseCrashlytics? _crashlytics;
  bool _didInit = false;

  /// Must be called after [Firebase.initializeApp].
  Future<void> initialize() async {
    if (_didInit) {
      return;
    }

    _didInit = true;

    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      _crashlytics = FirebaseCrashlytics.instance;
      // Disable in debug to keep console clean.
      await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (_) {
      _crashlytics = null;
    }
  }

  /// Sets user identifier so crash reports can be correlated.
  Future<void> identifyUser(String userId) async {
    await _crashlytics?.setUserIdentifier(userId);
  }

  /// Clears user identifier on sign-out.
  Future<void> clearUser() async {
    await _crashlytics?.setUserIdentifier('');
  }

  /// Records a non-fatal error with optional stack trace.
  Future<void> recordError(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) async {
    await _crashlytics?.recordError(
      error,
      stackTrace ?? StackTrace.current,
      reason: reason,
      fatal: fatal,
    );
  }

  /// Sets a custom key-value pair for enriching crash reports.
  Future<void> setCustomKey(String key, Object value) async {
    await _crashlytics?.setCustomKey(key, value);
  }

  /// Logs a breadcrumb message that appears alongside crashes.
  Future<void> log(String message) async {
    await _crashlytics?.log(message);
  }

  bool get isAvailable => _crashlytics != null;
}
