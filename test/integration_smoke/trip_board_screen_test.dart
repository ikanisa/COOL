import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

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
  group('Trip board smoke', () {
    late MockMobilityRepository mobilityRepository;

    setUpAll(() {
      registerFallbackValue(TripType.passenger);
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
      when(() => mobilityRepository.getMyTrips(any())).thenAnswer(
        (_) async => const [],
      );
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

      expect(find.text('Trip board'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Explore trips'), findsOneWidget);
      expect(find.text('Post trip'), findsOneWidget);
      expect(find.text('Passenger'), findsOneWidget);
      expect(find.text('Return trips'), findsOneWidget);
      expect(
        find.text('Browse trips, then continue on WhatsApp.'),
        findsNothing,
      );

      await tester.tap(find.text('My trips'));
      await settleTestApp(tester);

      expect(find.text('Manage your trips'), findsOneWidget);
      expect(find.text('No trips posted yet'), findsOneWidget);
      expect(find.text('Passenger'), findsNothing);
      expect(find.text('Return trips'), findsNothing);
    });
  });
}
