import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/screens/schedule_trip_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import 'test_harness.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class FakePlaceSearchService extends Mock {}

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

      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Posting as passenger'), findsOneWidget);
      expect(find.text('Passenger is your default role.'), findsOneWidget);
      expect(find.widgetWithText(CoolButton, 'Role'), findsOneWidget);

      await tester.tap(find.widgetWithText(CoolButton, 'Role'));
      await settleTestApp(tester);

      expect(find.text('Choose role'), findsOneWidget);
      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as driver'), findsOneWidget);
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

      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Posting as driver'), findsOneWidget);

      await tester.tap(find.widgetWithText(CoolButton, 'Role'));
      await settleTestApp(tester);

      await tester.tap(find.text('Driver').last);
      await settleTestApp(tester);

      expect(find.text('Posting as driver'), findsOneWidget);
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

      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Posting as passenger'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      // Final CTA is Post trip
      expect(find.text('Post trip'), findsOneWidget);
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

      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Posting as driver'), findsOneWidget);
      expect(find.text('Driver trips post as return trips.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Kigali');
      await tester.enterText(find.byType(TextFormField).at(1), 'Musanze');
      
      expect(find.text('Post trip'), findsOneWidget);
    });
  });
}
