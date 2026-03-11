import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Explicit platform/policy gate for Android MoMo SMS auto-read.
///
/// This keeps the Android M-Money SMS capability behind:
/// - Android platform support
/// - a build-time feature flag
/// - explicit user opt-in persisted locally
class MomoSmsPolicyService {
  MomoSmsPolicyService._();

  static final MomoSmsPolicyService instance = MomoSmsPolicyService._();

  static const _policyBox = 'momo_sms_policy';
  static const _userConsentKey = 'android_sms_user_consent';

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isBuildEnabled => const bool.fromEnvironment(
    'ENABLE_ANDROID_MOMO_SMS_AUTOREAD',
    // SMS auto-read is intentionally off until Android SMS permissions and
    // the live listener implementation are restored together.
    defaultValue: false,
  );

  /// The Android SMS listener is still a placeholder in this repo.
  ///
  /// Keep the feature fully hidden until the live listener, manifest
  /// permissions, and Play-policy-compliant rollout return together.
  bool get isRuntimeImplemented => false;

  bool get isFeatureAvailable =>
      isSupportedPlatform && isBuildEnabled && isRuntimeImplemented;

  Future<bool> hasUserConsent() async {
    if (!isFeatureAvailable) {
      return false;
    }

    final box = await Hive.openBox<dynamic>(_policyBox);
    return box.get(_userConsentKey, defaultValue: false) == true;
  }

  Future<void> setUserConsent(bool value) async {
    if (!isFeatureAvailable) {
      return;
    }

    final box = await Hive.openBox<dynamic>(_policyBox);
    await box.put(_userConsentKey, value);
  }
}
