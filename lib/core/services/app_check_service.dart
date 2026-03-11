import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      debugPrint('[AppCheck] ⚠️ Firebase not initialized — skipping');
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
      debugPrint('[AppCheck] ✅ Activated');
    } catch (e) {
      debugPrint('[AppCheck] ⚠️ Activation failed: $e — continuing without');
    }
  }

  /// Returns the current App Check token, or null if unavailable.
  static Future<String?> getToken({bool forceRefresh = false}) async {
    if (!_initialized) return null;

    try {
      return await FirebaseAppCheck.instance.getToken(forceRefresh);
    } catch (e) {
      debugPrint('[AppCheck] Token fetch failed: $e');
      return null;
    }
  }
}
