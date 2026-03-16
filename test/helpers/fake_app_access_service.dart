import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/device_settings_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/momo/services/nfc_hce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FakeAppAccessService extends AppAccessService {
  FakeAppAccessService({
    Map<AppAccessPermission, AppAccessSnapshot>? snapshots,
    Map<AppAccessPermission, AppAccessSnapshot>? enableResponses,
    this.openSettingsResult = true,
  }) : _snapshots = snapshots ?? _defaultSnapshots(),
       _enableResponses = enableResponses ?? const {},
       super(
         openBox: _unusedOpenBox,
         locationService: _FakeLocationService(),
         deviceSettingsService: _FakeDeviceSettingsService(),
         nfcHceService: _FakeNfcHceService(),
       );

  final Map<AppAccessPermission, AppAccessSnapshot> _snapshots;
  final Map<AppAccessPermission, AppAccessSnapshot> _enableResponses;
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  final bool openSettingsResult;

  var openSettingsCalls = 0;

  @override
  ValueListenable<int> get changes => _changes;

  @override
  Future<AppAccessSnapshot> getSnapshot(AppAccessPermission permission) async {
    return _snapshots[permission]!;
  }

  @override
  Future<List<AppAccessSnapshot>> getSnapshots(
    List<AppAccessPermission> permissions,
  ) async {
    return permissions.map((permission) => _snapshots[permission]!).toList();
  }

  @override
  Future<AppAccessSnapshot> enableAndRequest(
    AppAccessPermission permission,
  ) async {
    final next =
        _enableResponses[permission] ??
        AppAccessSnapshot(
          permission: permission,
          kind: AppAccessStateKind.ready,
          enabledInApp: true,
          supportedOnDevice: true,
          systemGranted: true,
        );
    _snapshots[permission] = next;
    _changes.value++;
    return next;
  }

  @override
  Future<AppAccessSnapshot> disable(AppAccessPermission permission) async {
    final next = AppAccessSnapshot(
      permission: permission,
      kind: AppAccessStateKind.disabledInApp,
      enabledInApp: false,
      supportedOnDevice: true,
    );
    _snapshots[permission] = next;
    _changes.value++;
    return next;
  }

  @override
  Future<bool> openSystemSettings(AppAccessPermission permission) async {
    openSettingsCalls++;
    return openSettingsResult;
  }

  static Map<AppAccessPermission, AppAccessSnapshot> _defaultSnapshots() {
    return Map<AppAccessPermission, AppAccessSnapshot>.fromEntries(
      AppAccessPermission.values.map(
        (permission) => MapEntry(
          permission,
          AppAccessSnapshot(
            permission: permission,
            kind: AppAccessStateKind.ready,
            enabledInApp: true,
            supportedOnDevice: true,
            systemGranted: true,
          ),
        ),
      ),
    );
  }
}

Future<Box<bool>> _unusedOpenBox(String name) {
  throw UnimplementedError('Hive is not used by FakeAppAccessService');
}

class _FakeDeviceSettingsService extends DeviceSettingsService {
  @override
  Future<bool> openNfcSettings() async => true;
}

class _FakeNfcHceService extends NfcHceService {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> isPaymentRequestActive() async => false;
}

class _FakeLocationService implements LocationService {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return 0;
  }

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Future<Position?> getLastKnownLocation() async => null;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return true;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<void> startLocationUpdates(ValueChanged<Position> onUpdate) async {}

  @override
  Future<void> stopLocationUpdates() async {}
}
