import 'dart:io';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_mobility_location');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    await AppAccessService.instance.setEnabled(
      AppAccessPermission.location,
      true,
    );
  });

  tearDown(() async {
    if (Hive.isBoxOpen(AppAccessService.boxName)) {
      await Hive.box<bool>(AppAccessService.boxName).clear();
      await Hive.box<bool>(AppAccessService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(AppAccessService.boxName);
    if (Hive.isBoxOpen('mobility_location_cache')) {
      await Hive.box<dynamic>('mobility_location_cache').clear();
      await Hive.box<dynamic>('mobility_location_cache').close();
    }
    await Hive.deleteBoxFromDisk('mobility_location_cache');
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  test(
    'bootstrap respects the in-app location access toggle from profile settings',
    () async {
      await AppAccessService.instance.setEnabled(
        AppAccessPermission.location,
        false,
      );
      final notifier = MobilityLocationNotifier(
        service: FakeLocationService(permission: LocationPermission.whileInUse),
      );

      await notifier.bootstrap();

      expect(notifier.state.status, MobilityLocationStatus.accessDisabled);
      expect(notifier.state.hasLocation, isFalse);
    },
  );

  test(
    'bootstrap requests rationale when permission has not been granted yet',
    () async {
      final notifier = MobilityLocationNotifier(
        service: FakeLocationService(permission: LocationPermission.denied),
      );

      await notifier.bootstrap();

      expect(notifier.state.status, MobilityLocationStatus.needsPermission);
      expect(notifier.state.hasLocation, isFalse);
    },
  );

  test('requestForegroundAccess resolves a precise current location', () async {
    final notifier = MobilityLocationNotifier(
      service: FakeLocationService(
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.whileInUse,
        currentPosition: fakePosition(latitude: -1.9441, longitude: 30.0619),
      ),
    );

    await notifier.requestForegroundAccess();

    expect(notifier.state.status, MobilityLocationStatus.ready);
    expect(
      notifier.state.position,
      const GeoPoint(latitude: -1.9441, longitude: 30.0619),
    );
    expect(notifier.state.isStale, isFalse);
  });

  test(
    'bootstrap surfaces approximate location when platform reports reduced accuracy',
    () async {
      final notifier = MobilityLocationNotifier(
        service: FakeLocationService(
          permission: LocationPermission.whileInUse,
          accuracyStatus: LocationAccuracyStatus.reduced,
          currentPosition: fakePosition(latitude: -1.95, longitude: 30.06),
        ),
      );

      await notifier.bootstrap();

      expect(notifier.state.status, MobilityLocationStatus.approximateReady);
      expect(notifier.state.isApproximate, isTrue);
    },
  );

  test(
    'bootstrap reports service-disabled state when device location is off',
    () async {
      final notifier = MobilityLocationNotifier(
        service: FakeLocationService(
          serviceEnabled: false,
          permission: LocationPermission.whileInUse,
        ),
      );

      await notifier.bootstrap();

      expect(notifier.state.status, MobilityLocationStatus.serviceDisabled);
      expect(notifier.state.hasLocation, isFalse);
    },
  );
}

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    LocationPermission? requestedPermission,
    this.accuracyStatus = LocationAccuracyStatus.precise,
    this.lastKnownPosition,
    this.currentPosition,
  }) : requestedPermission = requestedPermission ?? permission;

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission requestedPermission;
  LocationAccuracyStatus accuracyStatus;
  Position? lastKnownPosition;
  Position? currentPosition;
  bool trackingStarted = false;
  bool trackingStopped = false;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permission = requestedPermission;
    return permission;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracyStatus;

  @override
  Future<Position?> getLastKnownLocation() async => lastKnownPosition;

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async {
    final position = currentPosition;
    if (position == null) {
      throw StateError('No fake current position configured.');
    }
    return position;
  }

  @override
  Future<void> startLocationUpdates(void Function(Position p1) onUpdate) async {
    trackingStarted = true;
  }

  @override
  Future<void> stopLocationUpdates() async {
    trackingStopped = true;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    final deltaLat = lat2 - lat1;
    final deltaLng = lng2 - lng1;
    return deltaLat.abs() + deltaLng.abs();
  }

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return calculateDistance(
          userPos.latitude,
          userPos.longitude,
          targetLat,
          targetLng,
        ) <=
        10;
  }
}

Position fakePosition({
  required double latitude,
  required double longitude,
  DateTime? timestamp,
  double accuracy = 18,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime(2026, 3, 10, 12),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
