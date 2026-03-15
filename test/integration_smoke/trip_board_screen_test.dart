import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/models/trip_type.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/screens/trip_board_screen.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Trip board smoke', () {
    late MockMobilityRepository mobilityRepository;
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('cool_trip_board');
      Hive.init(hiveDir.path);
      registerFallbackValue(TripType.passenger);
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

      when(
        () => mobilityRepository.getScheduledTrips(
          any(),
          any(),
          any(),
          any(),
          any(),
        ),
      ).thenAnswer((_) async => const []);
      when(
        () => mobilityRepository.getMyTrips(any()),
      ).thenAnswer((_) async => const []);
    });

    testWidgets('explore and my-trips modes keep one clear header path', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const TripBoardScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Trip Board'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('My trips'), findsOneWidget);
      expect(find.text('Results'), findsOneWidget);
      expect(find.textContaining('Passenger trips'), findsOneWidget);
      expect(find.text('Trip type'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(
        find.text('Browse trips, then continue on WhatsApp.'),
        findsNothing,
      );

      await tester.tap(find.text('Trip type'));
      await settleTestApp(tester);

      expect(find.text('Driver returns'), findsWidgets);
      await tester.tap(find.text('Driver returns').last);
      await settleTestApp(tester);

      expect(find.text('Driver returns · All vehicle types'), findsOneWidget);

      await tester.tap(find.text('Filters'));
      await settleTestApp(tester);

      expect(find.text('Vehicle filter'), findsOneWidget);
      await tester.tap(find.text('Moto').last);
      await settleTestApp(tester);

      expect(find.text('Driver returns · Moto only'), findsOneWidget);

      await tester.tap(find.text('My trips'));
      await settleTestApp(tester);

      expect(find.text('Manage your trips'), findsOneWidget);
      expect(find.text('No trips posted yet'), findsOneWidget);
      expect(find.text('Trip type'), findsNothing);
      expect(find.text('Filters'), findsNothing);
    });
  });
}
