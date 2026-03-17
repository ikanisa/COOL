import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
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
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rs_membership_package.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/screens/rayon/tickets_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import '../test/integration_smoke/test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

class MockTripRepository extends Mock implements TripRepository {}

class MockVehicleTypeRepository extends Mock implements VehicleTypeRepository {}

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

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
    throw StateError('Location unavailable in integration tests.');
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

void main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
    registerFallbackValue(TripType.passenger);
  });

  group('Critical journeys', () {
    testWidgets('signed-out deep links preserve their redirect target', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: '/momo?amount=5000',
        session: null,
        user: null,
      );

      // Should land on onboarding or OTP
      expect(find.text('Welcome to Cool'), findsOneWidget);

      // Sign in via the notifier
      final authNotifier = app.container.read(authProvider.notifier);
      await authNotifier.verifyOtp('+250788123456', '123456');
      await settleTestApp(tester);

      // Should redirect to MoMo
      expect(find.byType(MomoScreen), findsOneWidget);
    });

    testWidgets('mobility hub renders explore and my-trips modes keep one clear header path', (tester) async {
      final mobilityRepository = MockMobilityRepository();
      final subscriptionRepository = MockSubscriptionRepository();
      final tripRepository = MockTripRepository();
      final vehicleTypeRepository = MockVehicleTypeRepository();

      when(() => mobilityRepository.getDriverProfile(any())).thenAnswer((_) async => null);
      when(() => mobilityRepository.getMyTrips(any())).thenAnswer((_) async => const []);
      when(() => mobilityRepository.getNearbyDrivers(any(), any(), any(), any())).thenAnswer((_) async => const []);
      when(() => mobilityRepository.getScheduledTrips(any(), any(), any(), any(), any())).thenAnswer((_) async => const []);
      when(() => subscriptionRepository.getSubscriptionStatus(any())).thenAnswer(
        (_) async => SubscriptionStatus.freeTier(driverId: 'user-1', tripsUsed: 0),
      );
      when(() => vehicleTypeRepository.fetchAll()).thenAnswer((_) async => const <VehicleType>[]);

      await pumpScopedApp(
        tester,
        child: const MobilityHomeScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          subscriptionRepositoryProvider.overrideWithValue(subscriptionRepository),
          mobilityTripRepositoryProvider.overrideWithValue(tripRepository),
          vehicleTypeRepositoryProvider.overrideWithValue(vehicleTypeRepository),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      expect(find.text('Mobility'), findsOneWidget);
      expect(find.text('Nearby'), findsOneWidget);
      
      await tester.tap(find.text('Trips'));
      await settleTestApp(tester);
      
      expect(find.text('No scheduled trips found'), findsOneWidget);
    });

    testWidgets('tickets hub renders the premium membership hero', (tester) async {
      final repository = MockRayonSportsRepository();
      final match = RsMatch(
        id: 'm1',
        homeTeam: 'Rayon Sports FC',
        awayTeam: 'APR FC',
        competition: 'Rwanda Premier League',
        venue: 'Amahoro Stadium',
        matchDate: DateTime.now().add(const Duration(days: 2)),
        kickoffTime: '15:00',
        isOnSale: true,
        ticketGeneralPrice: 5000,
        ticketVipPrice: 20000,
        saleStartsAt: DateTime.now().subtract(const Duration(days: 1)),
        capacity: 30000,
      );

      when(() => repository.getMatches(any(), any())).thenAnswer((_) async => [match]);
      when(() => repository.getFanMembership(any(), any())).thenAnswer((_) async => null);
      when(() => repository.getMembershipPackages(partnerId: any(named: 'partnerId'))).thenAnswer((_) async => []);
      when(() => repository.getMyTickets(any())).thenAnswer((_) async => []);

      await pumpScopedApp(
        tester,
        child: const TicketsScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          rayonSportsRepositoryProvider.overrideWithValue(repository),
        ],
      );

      // Wait for async providers to resolve
      await settleTestApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('APR FC'), findsOneWidget);
    });
  });
}
