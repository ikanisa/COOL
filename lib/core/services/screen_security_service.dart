/// Service to protect sensitive screens from screenshots and screen recording.
///
/// Prefers the cross-platform `no_screenshot` plugin so route wrappers work on
/// both Android and iOS, and falls back to the native method channel when the
/// plugin is unavailable.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:no_screenshot/no_screenshot.dart';

class ScreenSecurityService {
  ScreenSecurityService({MethodChannel? channel, NoScreenshot? noScreenshot})
    : _channel = channel ?? const MethodChannel('app.cool.mobile/security'),
      _noScreenshot = noScreenshot ?? NoScreenshot.instance;

  final MethodChannel _channel;
  final NoScreenshot _noScreenshot;

  bool _isSecure = false;

  /// Whether the screen is currently in secure mode.
  bool get isSecure => _isSecure;

  /// Enables secure mode — blocks screenshots and screen recording.
  ///
  /// Safe to call multiple times; the platform side is idempotent.
  Future<void> enableSecureMode() async {
    if (_isSecure) return;
    if (await _toggleWithPlugin(enable: true)) {
      _isSecure = true;
      return;
    }
    try {
      await _channel.invokeMethod<void>('enableSecureMode');
      _isSecure = true;
    } catch (e) {
      _debugLogFailure(
        prefix: '[ScreenSecurity] Failed to enable secure mode',
        error: e,
      );
    }
  }

  /// Disables secure mode — re-allows screenshots.
  ///
  /// Must be called when leaving a sensitive screen to avoid locking the
  /// entire app.
  Future<void> disableSecureMode() async {
    if (!_isSecure) return;
    if (await _toggleWithPlugin(enable: false)) {
      _isSecure = false;
      return;
    }
    try {
      await _channel.invokeMethod<void>('disableSecureMode');
      _isSecure = false;
    } catch (e) {
      _debugLogFailure(
        prefix: '[ScreenSecurity] Failed to disable secure mode',
        error: e,
      );
    }
  }

  Future<bool> _toggleWithPlugin({required bool enable}) async {
    try {
      if (enable) {
        await _noScreenshot.screenshotOff();
      } else {
        await _noScreenshot.screenshotOn();
      }
      return true;
    } catch (e) {
      _debugLogFailure(
        prefix:
            '[ScreenSecurity] no_screenshot ${enable ? 'enable' : 'disable'} failed',
        error: e,
      );
      return false;
    }
  }

  void _debugLogFailure({required String prefix, required Object error}) {
    if (error is MissingPluginException) {
      return;
    }
    debugPrint('$prefix: $error');
  }
}
