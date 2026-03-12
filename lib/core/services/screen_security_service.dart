/// Service to protect sensitive screens from screenshots and screen recording.
///
/// Uses platform channels to toggle Android's `FLAG_SECURE` and iOS's
/// secure view handling. Screens that show financial data (MoMo, credit)
/// should call [enableSecureMode] in `initState` and [disableSecureMode]
/// in `dispose`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenSecurityService {
  ScreenSecurityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.cool.mobile/security');

  final MethodChannel _channel;

  bool _isSecure = false;

  /// Whether the screen is currently in secure mode.
  bool get isSecure => _isSecure;

  /// Enables secure mode — blocks screenshots and screen recording.
  ///
  /// Safe to call multiple times; the platform side is idempotent.
  Future<void> enableSecureMode() async {
    if (_isSecure) return;
    try {
      await _channel.invokeMethod<void>('enableSecureMode');
      _isSecure = true;
    } catch (e) {
      debugPrint('[ScreenSecurity] Failed to enable secure mode: $e');
    }
  }

  /// Disables secure mode — re-allows screenshots.
  ///
  /// Must be called when leaving a sensitive screen to avoid locking the
  /// entire app.
  Future<void> disableSecureMode() async {
    if (!_isSecure) return;
    try {
      await _channel.invokeMethod<void>('disableSecureMode');
      _isSecure = false;
    } catch (e) {
      debugPrint('[ScreenSecurity] Failed to disable secure mode: $e');
    }
  }
}
