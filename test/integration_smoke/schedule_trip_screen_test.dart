import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/screens/schedule_trip_screen.dart';
import 'package:cool_app/features/mobility/services/place_search_service.dart';

import 'package:geolocator/geolocator.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class FakePlaceSearchService extends Mock implements PlaceSearchService {}

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
    throw StateError('Location unavailable in schedule trip test.');
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
  group('Schedule trip smoke', () {
    late MockMobilityRepository mobilityRepository;

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

      expect(find.text('Schedule a Trip'), findsOneWidget);
      expect(find.text('Posting as passenger'), findsOneWidget);

      // Role row is a GestureDetector tappable area
      await tester.tap(find.text('Posting as passenger'));
      await settleTestApp(tester);

      expect(find.text('Choose role'), findsOneWidget);
      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as driver'), findsOneWidget);
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

      expect(find.text('Schedule a Trip'), findsOneWidget);
      expect(find.text('Posting as driver'), findsOneWidget);

      await tester.tap(find.text('Posting as driver'));
      await settleTestApp(tester);

      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as driver'), findsOneWidget);
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

      expect(find.text('Schedule a Trip'), findsOneWidget);
      expect(find.text('Posting as passenger'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      // Final CTA is Post Trip on Board
      expect(find.text('Post Trip on Board'), findsOneWidget);
    });

    testWidgets('driver entry applies defaults and cleaner review copy', (
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
          placeSearchServiceProvider.overrideWithValue(
            FakePlaceSearchService(),
          ),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Schedule a Trip'), findsOneWidget);
      expect(find.text('Posting as driver'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      
      expect(find.text('Post Trip on Board'), findsOneWidget);
    });
  });
}
