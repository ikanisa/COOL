import 'dart:io';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/device_settings_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/momo/services/nfc_hce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_app_access');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(AppAccessService.boxName)) {
      await Hive.box<bool>(AppAccessService.boxName).clear();
      await Hive.box<bool>(AppAccessService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(AppAccessService.boxName);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  test('emits change notifications when access changes in app', () async {
    final service = AppAccessService(
      openBox: Hive.openBox<bool>,
      locationService: _FakeLocationService(),
      deviceSettingsService: _FakeDeviceSettingsService(),
      nfcHceService: _FakeNfcHceService(supported: true),
    );
    var notifications = 0;

    service.changes.addListener(() => notifications++);

    await service.setEnabled(AppAccessPermission.nfc, false);
    await service.setEnabled(AppAccessPermission.nfc, false);
    await service.setEnabled(AppAccessPermission.nfc, true);

    expect(notifications, 2);
  });

  test('disabling nfc stops an active tap receive session', () async {
    final nfcHceService = _FakeNfcHceService(active: true);
    final service = AppAccessService(
      openBox: Hive.openBox<bool>,
      locationService: _FakeLocationService(),
      deviceSettingsService: _FakeDeviceSettingsService(),
      nfcHceService: nfcHceService,
    );

    final snapshot = await service.disable(AppAccessPermission.nfc);

    expect(snapshot.kind, AppAccessStateKind.disabledInApp);
    expect(nfcHceService.stopCalls, 1);
    expect(nfcHceService.active, isFalse);
  });

  test(
    'sms access defaults off inside COOL until explicitly enabled',
    () async {
      final service = AppAccessService(
        openBox: Hive.openBox<bool>,
        locationService: _FakeLocationService(),
        deviceSettingsService: _FakeDeviceSettingsService(),
        nfcHceService: _FakeNfcHceService(supported: true),
      );

      expect(await service.isEnabled(AppAccessPermission.sms), isFalse);
    },
  );
}

class _FakeDeviceSettingsService extends DeviceSettingsService {
  @override
  Future<bool> openNfcSettings() async => true;
}

class _FakeNfcHceService extends NfcHceService {
  _FakeNfcHceService({this.supported = true, this.active = false});

  final bool supported;
  bool active;
  var stopCalls = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isPaymentRequestActive() async => active;

  @override
  Future<void> stopPaymentRequest() async {
    stopCalls++;
    active = false;
  }
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
