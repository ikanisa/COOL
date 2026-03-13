import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/router/app_router.dart';
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
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(TripType.passenger);
  });

  group('Critical journeys', () {
    testWidgets('signed-out deep links preserve their redirect target', (
      tester,
    ) async {
      const registerLink = '/register?phone=%2B250788123456';
      final app = await pumpRouterApp(tester, initialLocation: registerLink);

      final uri = app.router.routeInformationProvider.value.uri;

      expect(uri.path, AppRoutes.onboarding);
      expect(uri.queryParameters['redirect'], registerLink);
    });

    testWidgets('OTP validation blocks an empty phone number', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Enter your phone number'), findsOneWidget);
    });

    testWidgets('MoMo send flow validates recipient and amount', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
      );

      await tester.tap(find.widgetWithText(CoolButton, 'Send money'));
      await settleTestApp(tester);
      await tester.tap(find.text('Confirm Send'));
      await settleTestApp(tester);

      expect(find.text('Enter a valid recipient and amount.'), findsOneWidget);
    });

    testWidgets('Mobility home stays usable without location services', (
      tester,
    ) async {
      final mobilityRepository = MockMobilityRepository();
      final subscriptionRepository = MockSubscriptionRepository();
      final tripRepository = MockTripRepository();
      final vehicleTypeRepository = MockVehicleTypeRepository();

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
      when(
        () => subscriptionRepository.getSubscriptionStatus(any()),
      ).thenAnswer(
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
      expect(find.text('Turn on location services'), findsOneWidget);
      expect(find.text('📅 Schedule a Trip'), findsOneWidget);
    });

    testWidgets('tickets hub renders the premium membership hero', (
      tester,
    ) async {
      final repository = MockRayonSportsRepository();
      final membership = FanMembership(
        id: 'membership-1',
        userId: 'user-1',
        partnerId: 'partner-1',
        displayName: 'Alex Fan',
        tier: FanTier.gold,
        points: 2200,
        chapter: 'Kigali Central',
        membershipNumber: 'RS-2026-AAA111',
        joinedAt: DateTime(2026, 1, 1),
      );
      final match = RsMatch(
        id: 'match-1',
        homeTeam: 'Rayon Sports',
        awayTeam: 'APR FC',
        competition: 'RPL',
        venue: 'Amahoro',
        matchDate: DateTime(2026, 4, 1),
        kickoffTime: '18:00',
        isOnSale: true,
        ticketGeneralPrice: 3000,
        ticketVipPrice: 6000,
        saleStartsAt: DateTime(2026, 3, 20),
        capacity: 1000,
      );
      final ticket = RsTicket(
        id: 'ticket-1',
        matchId: match.id,
        match: match,
        userId: 'user-1',
        seatType: SeatType.general,
        amountPaid: 3000,
        qrCode: 'qr-1',
        momoReference: 'momo-1',
        status: TicketStatus.valid,
        purchasedAt: DateTime(2026, 3, 25),
      );

      when(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).thenAnswer((_) async => membership);
      when(
        () => repository.getMatches('partner-1', false),
      ).thenAnswer((_) async => <RsMatch>[match]);
      when(
        () => repository.getMyTickets('user-1'),
      ).thenAnswer((_) async => <RsTicket>[ticket]);

      await pumpScopedApp(
        tester,
        child: const TicketsScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          rayonSportsRepositoryProvider.overrideWithValue(repository),
          rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
          rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
        ],
      );

      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('Secure your seat early.'), findsOneWidget);
      expect(find.text('⭐ GOLD — Early Access'), findsOneWidget);
      expect(find.text('On Sale (1)'), findsOneWidget);
    });
  });
}
