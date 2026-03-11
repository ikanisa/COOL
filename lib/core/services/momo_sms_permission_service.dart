import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MomoSmsPermissionStatus {
  supportedGranted,
  supportedDenied,
  supportedPermanentlyDenied,
  unsupported,
}

/// Centralized SMS permission handling for Android-only MoMo SMS detection.
///
/// iOS does not permit third-party apps to read incoming SMS, so this service
/// returns [MomoSmsPermissionStatus.unsupported] there.
class MomoSmsPermissionService {
  MomoSmsPermissionService._();

  static final MomoSmsPermissionService instance = MomoSmsPermissionService._();

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<MomoSmsPermissionStatus> getStatus() async {
    if (!isSupported) {
      return MomoSmsPermissionStatus.unsupported;
    }

    final status = await Permission.sms.status;
    if (status.isGranted || status.isLimited) {
      return MomoSmsPermissionStatus.supportedGranted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MomoSmsPermissionStatus.supportedPermanentlyDenied;
    }

    return MomoSmsPermissionStatus.supportedDenied;
  }

  Future<MomoSmsPermissionStatus> ensureGranted() async {
    if (!isSupported) {
      return MomoSmsPermissionStatus.unsupported;
    }

    final current = await getStatus();
    if (current == MomoSmsPermissionStatus.supportedGranted ||
        current == MomoSmsPermissionStatus.supportedPermanentlyDenied) {
      return current;
    }

    final requested = await Permission.sms.request();
    if (requested.isGranted || requested.isLimited) {
      return MomoSmsPermissionStatus.supportedGranted;
    }
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      return MomoSmsPermissionStatus.supportedPermanentlyDenied;
    }

    return MomoSmsPermissionStatus.supportedDenied;
  }

  Future<bool> openSettings() {
    if (!isSupported) {
      return Future<bool>.value(false);
    }

    return openAppSettings();
  }
}
