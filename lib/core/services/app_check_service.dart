import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

const _log = AppLogger('AppCheck');

/// Initializes Firebase App Check for request attestation.
///
/// Uses Play Integrity (Android) and App Attest (iOS) in release builds.
/// Falls back to the debug provider during development.
class AppCheckService {
  AppCheckService._();

  static bool _initialized = false;

  /// Activates App Check. Safe to call even if Firebase is not initialized.
  static Future<void> initialize() async {
    if (_initialized) return;

    if (Firebase.apps.isEmpty) {
      _log.info('Firebase not initialized — skipping');
      return;
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
      _initialized = true;
      _log.info('Activated');
    } catch (e) {
      _log.warn('Activation failed: $e — continuing without');
    }
  }

  /// Returns the current App Check token, or null if unavailable.
  static Future<String?> getToken({bool forceRefresh = false}) async {
    if (!_initialized) return null;

    try {
      return await FirebaseAppCheck.instance.getToken(forceRefresh);
    } catch (e) {
      _log.warn('Token fetch failed: $e');
      return null;
    }
  }

  /// Returns a one-time token for replay-protected custom backend requests.
  static Future<String?> getLimitedUseToken() async {
    if (!_initialized) return null;

    try {
      return await FirebaseAppCheck.instance.getLimitedUseToken();
    } catch (e) {
      _log.warn('Limited-use token fetch failed: $e');
      return null;
    }
  }

  /// Returns a limited-use token or throws when device attestation is missing.
  static Future<String> requireLimitedUseToken({
    String featureName = 'This action',
  }) async {
    final token = await getLimitedUseToken();
    if (token == null || token.isEmpty) {
      throw StateError(
        '$featureName requires device attestation. Check Firebase App Check configuration and try again.',
      );
    }

    return token;
  }
}
