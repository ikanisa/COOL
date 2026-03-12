import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/screens/schedule_trip_screen.dart';

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
  group('Schedule trip smoke', () {
    late MockMobilityRepository mobilityRepository;

    setUp(() {
      mobilityRepository = MockMobilityRepository();
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
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Pickup and destination'), findsOneWidget);
      expect(find.text('Route → Time → Options → Review'), findsNothing);
      expect(find.text('Turn on device location'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('When'), findsOneWidget);
      expect(find.text('Return or repeat'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Trip setup'), findsOneWidget);
      expect(find.text('Ride options'), findsNothing);
      expect(find.text('Add details'), findsOneWidget);

      await tester.tap(find.text('Review').last);
      await settleTestApp(tester);

      expect(
        find.text('Check the main trip details before posting.'),
        findsOneWidget,
      );
      expect(find.text('No return trip'), findsOneWidget);
      expect(find.text('One-time trip'), findsOneWidget);
    });
  });
}
