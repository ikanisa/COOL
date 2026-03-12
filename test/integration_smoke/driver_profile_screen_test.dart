import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/mobility/models/driver_profile.dart';
import 'package:cool_app/features/mobility/models/subscription_status.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/subscription_repository.dart';
import 'package:cool_app/features/mobility/screens/driver_profile_screen.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

void main() {
  group('Driver profile smoke', () {
    late MockMobilityRepository mobilityRepository;
    late MockSubscriptionRepository subscriptionRepository;

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

    testWidgets('keeps overview focused and moves setup into manage', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const DriverProfileScreen(),
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Moto Taxi'),
        overrides: <Override>[
          mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
          subscriptionRepositoryProvider.overrideWithValue(
            subscriptionRepository,
          ),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Driver dashboard'), findsOneWidget);
      expect(find.text('Add return trip'), findsOneWidget);
      expect(find.text('Manage vehicle and plan'), findsOneWidget);
      expect(find.text('Today\'s trips'), findsOneWidget);
      expect(find.text('Vehicle and plan'), findsNothing);

      await tester.tap(find.text('Manage'));
      await settleTestApp(tester);

      expect(find.text('Vehicle and plan'), findsOneWidget);
      expect(find.text('Edit vehicle'), findsOneWidget);
      expect(find.text('Add return trip'), findsNothing);
      expect(find.text('Today\'s trips'), findsNothing);
    });
  });
}
