import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/config/env_config.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/models/subscription_status.dart';
import 'package:cool_app/features/mobility/models/trip_type.dart';
import 'package:cool_app/features/mobility/models/vehicle_type.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/providers/vehicle_type_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/subscription_repository.dart';
import 'package:cool_app/features/mobility/repositories/trip_repository.dart';
import 'package:cool_app/features/mobility/repositories/vehicle_type_repository.dart';
import 'package:cool_app/features/mobility/screens/mobility_home_screen.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

class MockTripRepository extends Mock implements TripRepository {}

class MockVehicleTypeRepository extends Mock implements VehicleTypeRepository {}

class DisabledLocationService implements LocationService {
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
  }) {
    throw StateError('Location unavailable in integration smoke tests.');
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    return LocationAccuracyStatus.precise;
  }

  @override
  Future<Position?> getLastKnownLocation() async => null;

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return false;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<void> startLocationUpdates(void Function(Position) onUpdate) async {}

  @override
  Future<void> stopLocationUpdates() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(TripType.passenger);
  });

  late MockMobilityRepository mobilityRepository;
  late MockSubscriptionRepository subscriptionRepository;
  late MockTripRepository tripRepository;
  late MockVehicleTypeRepository vehicleTypeRepository;
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_trip_offline');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    for (final boxName in <String>[
      AppAccessService.boxName,
      'mobility_location_cache',
    ]) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<dynamic>(boxName).clear();
        await Hive.box<dynamic>(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    mobilityRepository = MockMobilityRepository();
    subscriptionRepository = MockSubscriptionRepository();
    tripRepository = MockTripRepository();
    vehicleTypeRepository = MockVehicleTypeRepository();

    when(
      () => mobilityRepository.getDriverProfile(any()),
    ).thenAnswer((_) async => null);
    when(
      () => mobilityRepository.getMyTrips(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => mobilityRepository.getNearbyDrivers(any(), any(), any(), any()),
    ).thenAnswer((_) async => const []);
    when(
      () => mobilityRepository.getScheduledTrips(
        any(),
        any(),
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async => const []);
    when(() => subscriptionRepository.getSubscriptionStatus(any())).thenAnswer(
      (_) async =>
          SubscriptionStatus.freeTier(driverId: 'user-1', tripsUsed: 0),
    );
    when(() => vehicleTypeRepository.fetchAll()).thenAnswer(
      (_) async => const <VehicleType>[
        VehicleType(id: 'all', label: 'All', value: 'All', emoji: '🚘'),
        VehicleType(id: 'moto', label: 'Moto', value: 'Moto', emoji: '🛺'),
        VehicleType(id: 'cab', label: 'Cab', value: 'Cab', emoji: '🚗'),
      ],
    );
  });

  testWidgets(
    'Mobility home stays usable when location services are disabled',
    (tester) async {
      await pumpScopedApp(
        tester,
        child: const MobilityHomeScreen(),
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Moto'),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          subscriptionRepositoryProvider.overrideWithValue(
            subscriptionRepository,
          ),
          mobilityTripRepositoryProvider.overrideWithValue(tripRepository),
          vehicleTypeRepositoryProvider.overrideWithValue(
            vehicleTypeRepository,
          ),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      expect(find.text('Mobility'), findsOneWidget);
      expect(find.text('Find or post a ride'), findsOneWidget);
      expect(find.text('Nearby drivers'), findsOneWidget);
      expect(find.text('All vehicle types'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Schedule trip'), findsOneWidget);
      expect(find.text('Manage driver mode'), findsOneWidget);
      expect(
        find.text('Show map'),
        EnvConfig.hasEmbeddedGoogleMapsSupport(TargetPlatform.android)
            ? findsOneWidget
            : findsNothing,
      );

      await tester.tap(find.text('Scheduled Trips'));
      await tester.pumpAndSettle();

      expect(find.text('Scheduled trips'), findsOneWidget);
      expect(find.text('Show map'), findsNothing);
    },
  );
}
