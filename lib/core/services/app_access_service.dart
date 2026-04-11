import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/momo/services/nfc_hce_service.dart';
import '../../features/momo/services/nfc_service.dart';
import 'hive_runtime.dart';
import 'device_settings_service.dart';

enum AppAccessPermission { contacts, camera, nfc, sms, photos }

enum AppAccessStateKind {
  ready,
  disabledInApp,
  needsSystemPermission,
  blockedInSystem,
  serviceDisabled,
  notAvailable,
}

class AppAccessSnapshot {
  const AppAccessSnapshot({
    required this.permission,
    required this.kind,
    required this.enabledInApp,
    required this.supportedOnDevice,
    this.systemGranted = false,
  });

  final AppAccessPermission permission;
  final AppAccessStateKind kind;
  final bool enabledInApp;
  final bool supportedOnDevice;
  final bool systemGranted;

  bool get isReady => kind == AppAccessStateKind.ready;
}

/// User-managed access preferences layered on top of system permissions.
///
/// This lets users disable feature access from inside Cool at any time, even
/// when the underlying OS permission is still granted.
class AppAccessService {
  AppAccessService({
    required OpenHiveBox<bool> openBox,
    DeviceSettingsService? deviceSettingsService,
    NfcHceService? nfcHceService,
  }) : _openBox = openBox,
       _deviceSettingsService =
           deviceSettingsService ?? DeviceSettingsService.instance,
       _nfcHceService = nfcHceService ?? NfcHceService.instance;

  static const boxName = 'app_access_preferences';
  static const _onboardingKey = 'permission_onboarding_complete';

  final OpenHiveBox<bool> _openBox;
  final DeviceSettingsService _deviceSettingsService;
  final NfcHceService _nfcHceService;
  final ValueNotifier<int> _changeRevision = ValueNotifier<int>(0);

  ValueListenable<int> get changes => _changeRevision;

  /// Whether the user has completed the one-time permission onboarding.
  Future<bool> hasCompletedPermissionOnboarding() async {
    final box = await _openBox(boxName);
    return box.get(_onboardingKey, defaultValue: false) ?? false;
  }

  /// Marks the one-time permission onboarding as complete.
  Future<void> markPermissionOnboardingComplete() async {
    final box = await _openBox(boxName);
    await box.put(_onboardingKey, true);
  }

  Future<bool> isEnabled(AppAccessPermission permission) async {
    final box = await _openBox(boxName);
    final defaultEnabled = _defaultEnabled(permission);
    return box.get(permission.name, defaultValue: defaultEnabled) ??
        defaultEnabled;
  }

  Future<void> setEnabled(AppAccessPermission permission, bool enabled) async {
    final box = await _openBox(boxName);
    final defaultEnabled = _defaultEnabled(permission);
    final current =
        box.get(permission.name, defaultValue: defaultEnabled) ??
        defaultEnabled;
    if (current == enabled) {
      return;
    }
    await box.put(permission.name, enabled);
    _changeRevision.value++;
  }

  Future<AppAccessSnapshot> getSnapshot(AppAccessPermission permission) async {
    if (permission == AppAccessPermission.sms && !_supportsSmsPermission) {
      return AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.notAvailable,
        enabledInApp: false,
        supportedOnDevice: false,
      );
    }

    final enabledInApp = await isEnabled(permission);
    if (!enabledInApp) {
      return AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.disabledInApp,
        enabledInApp: false,
        supportedOnDevice: true,
      );
    }

    return switch (permission) {
      AppAccessPermission.contacts => _permissionSnapshot(
        permission: permission,
        status: await Permission.contacts.status,
      ),
      AppAccessPermission.camera => _permissionSnapshot(
        permission: permission,
        status: await Permission.camera.status,
      ),
      AppAccessPermission.nfc => _nfcSnapshot(permission),
      AppAccessPermission.sms => _smsSnapshot(permission),
      AppAccessPermission.photos => _permissionSnapshot(
        permission: permission,
        status: await Permission.photos.status,
      ),
    };
  }

  Future<List<AppAccessSnapshot>> getSnapshots(
    List<AppAccessPermission> permissions,
  ) async {
    return Future.wait(permissions.map(getSnapshot));
  }

  Future<AppAccessSnapshot> enableAndRequest(
    AppAccessPermission permission,
  ) async {
    await setEnabled(permission, true);
    switch (permission) {
      case AppAccessPermission.contacts:
        await Permission.contacts.request();
        break;
      case AppAccessPermission.camera:
        await Permission.camera.request();
        break;
      case AppAccessPermission.nfc:
        break;
      case AppAccessPermission.sms:
        if (_supportsSmsPermission) {
          await Permission.sms.request();
        }
        break;
      case AppAccessPermission.photos:
        await Permission.photos.request();
        break;
    }
    return getSnapshot(permission);
  }

  Future<AppAccessSnapshot> disable(AppAccessPermission permission) async {
    await setEnabled(permission, false);
    if (permission == AppAccessPermission.nfc) {
      await _stopActiveNfcReceive();
    }
    return getSnapshot(permission);
  }

  Future<bool> openSystemSettings(AppAccessPermission permission) async {
    switch (permission) {
      case AppAccessPermission.nfc:
        return _deviceSettingsService.openNfcSettings();
      case AppAccessPermission.contacts:
      case AppAccessPermission.camera:
      case AppAccessPermission.sms:
      case AppAccessPermission.photos:
        return openAppSettings();
    }
  }

  Future<void> _stopActiveNfcReceive() async {
    try {
      if (!await _nfcHceService.isSupported()) {
        return;
      }
      if (!await _nfcHceService.isPaymentRequestActive()) {
        return;
      }
      await _nfcHceService.stopPaymentRequest();
    } catch (_) {
      // Access revocation should remain best-effort even if HCE cleanup fails.
    }
  }

  AppAccessSnapshot _permissionSnapshot({
    required AppAccessPermission permission,
    required PermissionStatus status,
  }) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.ready,
        enabledInApp: true,
        supportedOnDevice: true,
        systemGranted: true,
      );
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.blockedInSystem,
        enabledInApp: true,
        supportedOnDevice: true,
      );
    }

    return AppAccessSnapshot(
      permission: permission,
      kind: AppAccessStateKind.needsSystemPermission,
      enabledInApp: true,
      supportedOnDevice: true,
    );
  }

  Future<AppAccessSnapshot> _nfcSnapshot(AppAccessPermission permission) async {
    final status = await NfcService.checkAvailability();
    return switch (status) {
      NfcStatus.available => AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.ready,
        enabledInApp: true,
        supportedOnDevice: true,
        systemGranted: true,
      ),
      NfcStatus.disabled => AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.serviceDisabled,
        enabledInApp: true,
        supportedOnDevice: true,
      ),
      NfcStatus.notSupported => AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.notAvailable,
        enabledInApp: true,
        supportedOnDevice: false,
      ),
    };
  }

  Future<AppAccessSnapshot> _smsSnapshot(AppAccessPermission permission) async {
    if (!_supportsSmsPermission) {
      return AppAccessSnapshot(
        permission: permission,
        kind: AppAccessStateKind.notAvailable,
        enabledInApp: true,
        supportedOnDevice: false,
      );
    }

    return _permissionSnapshot(
      permission: permission,
      status: await Permission.sms.status,
    );
  }

  bool get _supportsSmsPermission {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid;
  }

  bool _defaultEnabled(AppAccessPermission permission) {
    // SMS access is restricted personal data and must remain explicit opt-in.
    if (permission == AppAccessPermission.sms) {
      return false;
    }
    return true;
  }
}
