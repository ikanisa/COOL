import 'dart:io';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/features/mobility/models/driver_profile.dart';
import 'package:cool_app/features/mobility/models/subscription_status.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/subscription_repository.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

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
    throw StateError('Location unavailable in driver smoke test.');
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

  group('Driver profile smoke', () {
    late MockMobilityRepository mobilityRepository;
    late MockSubscriptionRepository subscriptionRepository;
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('cool_driver_profile');
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

      final now = DateTime.now();
      final todayTrip = DateTime(now.year, now.month, now.day, 14);

      when(() => mobilityRepository.getDriverProfile(any())).thenAnswer(
        (_) async => DriverProfile(
          userId: 'user-1',
          fullName: 'Alex Driver',
          vehicleType: 'Moto Taxi',
          vehicleDescription: 'RAC 123 A',
          isRegularDriver: true,
          isOnline: true,
          credits: 3,
          vehicleStatus: 'approved',
          rating: 4.8,
          tripsDone: 12,
        ),
      );
      when(() => mobilityRepository.getMyTrips(any())).thenAnswer(
        (_) async => <Trip>[
          Trip(
            id: 'trip-1',
            userId: 'user-1',
            fromLocation: 'Kigali',
            toLocation: 'Musanze',
            departureTime: todayTrip,
            vehicleType: 'Moto Taxi',
          ),
        ],
      );
      when(
        () => subscriptionRepository.getSubscriptionStatus(any()),
      ).thenAnswer(
        (_) async => const SubscriptionStatus(
          driverId: 'user-1',
          status: 'free',
          tripsUsed: 12,
          tripsRemaining: 3,
        ),
      );
    });

    testWidgets(
      'keeps overview focused and opens vehicle and subscription as routes',
      (tester) async {
        final app = await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.mobilityDriver,
          session: fakeSession(),
          user: fakeUser(isDriver: true, vehicleType: 'Moto Taxi'),
          overrides: <Override>[
            mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
            subscriptionRepositoryProvider.overrideWithValue(
              subscriptionRepository,
            ),
            locationServiceProvider.overrideWithValue(
              DisabledLocationService(),
            ),
          ],
        );

        await settleTestApp(tester);

        expect(find.text('Driver dashboard'), findsOneWidget);
        expect(find.text('Add return trip'), findsOneWidget);
        final vehicleButton = find.widgetWithText(TextButton, 'Vehicle');
        final subscriptionButton = find.widgetWithText(
          TextButton,
          'Subscription',
        );
        expect(vehicleButton, findsOneWidget);
        expect(subscriptionButton, findsOneWidget);
        expect(find.text('Today\'s trips'), findsOneWidget);
        expect(find.text('Vehicle details'), findsNothing);

        await tester.tap(find.text('Add return trip'));
        await tester.pumpAndSettle();

        expect(find.text('Set your return route'), findsOneWidget);
        expect(find.text('Posting as Driver'), findsOneWidget);
        expect(find.text('Pickup and destination'), findsNothing);

        app.router.pop();
        await tester.pumpAndSettle();

        await tester.tap(vehicleButton);
        await tester.pumpAndSettle();

        expect(find.text('Vehicle details'), findsOneWidget);
        expect(find.text('Edit vehicle info'), findsOneWidget);
        expect(find.text('Posting readiness'), findsOneWidget);
        expect(find.text('Add return trip'), findsNothing);
        expect(find.text('Subscription access'), findsNothing);

        app.router.pop();
        await tester.pumpAndSettle();

        await tester.tap(subscriptionButton);
        await tester.pumpAndSettle();

        expect(find.text('Subscription access'), findsOneWidget);
        expect(find.text('Current access'), findsOneWidget);
        expect(find.text('Selected plan'), findsOneWidget);
        expect(find.text('Unlock Unlimited Trips'), findsOneWidget);
      },
    );

    testWidgets('shows active subscription details without upgrade banner', (
      tester,
    ) async {
      final now = DateTime.now();
      when(
        () => subscriptionRepository.getSubscriptionStatus(any()),
      ).thenAnswer(
        (_) async => SubscriptionStatus(
          driverId: 'user-1',
          status: 'active',
          tripsUsed: 18,
          tripsRemaining: -1,
          planId: 'moto',
          expiresAt: now.add(const Duration(days: 21)),
          createdAt: now.subtract(const Duration(days: 9)),
        ),
      );

      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.mobilityDriverSubscription,
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Moto Taxi'),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          subscriptionRepositoryProvider.overrideWithValue(
            subscriptionRepository,
          ),
          locationServiceProvider.overrideWithValue(DisabledLocationService()),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Subscription access'), findsOneWidget);
      expect(find.text('Current access'), findsOneWidget);
      expect(find.text('Renewal note'), findsOneWidget);
      expect(find.text('Unlock Unlimited Trips'), findsNothing);
      expect(find.text('Unlimited'), findsOneWidget);
    });
  });
}
