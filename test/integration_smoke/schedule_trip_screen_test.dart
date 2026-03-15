import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/screens/schedule_trip_screen.dart';
import 'package:cool_app/features/mobility/services/place_search_service.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class FakePlaceSearchService implements PlaceSearchService {
  @override
  Future<PlaceSearchResult?> geocodeQuery(
    String query, {
    GeoPoint? near,
    String? languageTag,
    int limit = 1,
  }) async => null;

  @override
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    GeoPoint? near,
    String? languageTag,
    String? sessionToken,
    int limit = 5,
  }) async => const [];

  @override
  Future<PlaceSearchResult> resolvePlace(
    PlaceSearchResult prediction, {
    String? languageTag,
    String? sessionToken,
  }) async => prediction;

  @override
  Future<PlaceSearchResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String? languageTag,
  }) async => null;

  @override
  Future<MobilityRoutePreview?> computeRoutePreview({
    required GeoPoint origin,
    required GeoPoint destination,
    String? languageTag,
    MobilityRouteTravelMode travelMode = MobilityRouteTravelMode.drive,
  }) async => null;
}

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

  group('Schedule trip smoke', () {
    late MockMobilityRepository mobilityRepository;
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('cool_schedule_trip');
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
    });

    testWidgets('defaults to passenger and shows the driver upgrade path', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ScheduleTripScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Set your route'), findsOneWidget);
      expect(find.text('Posting as Passenger'), findsOneWidget);
      expect(find.text('Passenger is your default role.'), findsOneWidget);
      expect(find.widgetWithText(CoolButton, 'Role'), findsOneWidget);

      await tester.tap(find.widgetWithText(CoolButton, 'Role'));
      await settleTestApp(tester);

      expect(find.text('Choose role'), findsOneWidget);
      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as Driver'), findsOneWidget);
      expect(
        find.text('Finish driver setup before posting as a driver.'),
        findsOneWidget,
      );
      expect(find.text('Become a driver'), findsOneWidget);
    });

    testWidgets('keeps driver scheduling available for driver-ready users', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ScheduleTripScreen(),
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Cab'),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      await settleTestApp(tester);

      await tester.tap(find.widgetWithText(CoolButton, 'Role'));
      await settleTestApp(tester);

      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as Driver'), findsOneWidget);
      expect(find.text('Driver trips post as return trips.'), findsOneWidget);
      expect(find.text('Become a driver'), findsNothing);
    });

    testWidgets('keeps one main card per step and protects the posting flow', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ScheduleTripScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
          placeSearchServiceProvider.overrideWithValue(
            FakePlaceSearchService(),
          ),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Pickup and destination'), findsOneWidget);
      expect(find.text('Set your route'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Return or repeat'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Trip setup'), findsOneWidget);
      expect(find.text('Ride options'), findsNothing);
      expect(find.text('Add details'), findsOneWidget);

      await tester.tap(find.text('Review').last);
      await settleTestApp(tester);

      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(
        find.text('Check the main trip details before posting.'),
        findsOneWidget,
      );
      expect(find.text('Posting behavior'), findsOneWidget);
      expect(
        find.text('Drivers see your route, timing, seats, and note.'),
        findsOneWidget,
      );
      expect(
        find.text('Text route only. Confirm the exact pickup in chat.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'If the network drops, COOL saves this trip on device and syncs it later.',
        ),
        findsOneWidget,
      );
      expect(find.text('No return trip'), findsOneWidget);
      expect(find.text('One-time trip'), findsOneWidget);
    });

    testWidgets('driver entry applies defaults and cleaner review copy', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ScheduleTripScreen(
          initialRole: ScheduleTripPostingRole.driver,
        ),
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Cab'),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
          placeSearchServiceProvider.overrideWithValue(
            FakePlaceSearchService(),
          ),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Set your return route'), findsOneWidget);
      expect(find.text('Posting as Driver'), findsOneWidget);
      expect(find.text('Driver trips post as return trips.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('Departure timing'), findsOneWidget);
      expect(find.text('Extra scheduling'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Driver return setup'), findsOneWidget);
      expect(find.text('Posting vehicle'), findsOneWidget);
      expect(find.text('Vehicle for this trip'), findsNothing);
      expect(find.text('Seats available'), findsOneWidget);
      expect(find.text('Rider note'), findsOneWidget);

      await tester.tap(find.text('Review').last);
      await settleTestApp(tester);

      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('Ready to post your driver return?'), findsOneWidget);
      expect(find.text('Trip type'), findsOneWidget);
      expect(find.text('Driver return'), findsOneWidget);
      expect(find.text('Seats available'), findsOneWidget);
      expect(find.text('Rider note'), findsOneWidget);
      expect(find.text('Posting behavior'), findsOneWidget);
      expect(
        find.text(
          'Riders see your route, timing, seats, vehicle, and rider note.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Riders contact you after posting. Final pickup, fare, and timing are agreed in WhatsApp.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Check the main trip details before posting.'),
        findsNothing,
      );
    });
  });
}
