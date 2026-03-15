import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/subscription_repository.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

void main() {
  late MockMobilityRepository mobilityRepository;
  late MockSubscriptionRepository subscriptionRepository;
  late DriverNotifier notifier;

  setUp(() {
    mobilityRepository = MockMobilityRepository();
    subscriptionRepository = MockSubscriptionRepository();

    notifier = DriverNotifier(
      authState: const AuthState(
        user: UserProfile(
          id: 'driver-1',
          phone: '+250788123456',
          fullName: 'Legacy Driver',
          momoNumber: '0788123456',
          momoProvider: 'mtn_momo_rw',
          country: 'RW',
          languageCode: 'en',
          isDriver: true,
          vehicleType: 'Moto',
        ),
      ),
      mobilityRepository: mobilityRepository,
      subscriptionRepository: subscriptionRepository,
    );
  });

  test(
    'falls back to auth metadata when legacy mobility schema is missing',
    () async {
      when(() => mobilityRepository.getDriverProfile(any())).thenThrow(
        const PostgrestException(
          message: 'column driver_profiles.country does not exist',
          code: '42703',
        ),
      );
      when(() => subscriptionRepository.getSubscriptionStatus(any())).thenThrow(
        const PostgrestException(
          message: 'relation driver_subscriptions does not exist',
          code: '42P01',
        ),
      );
      when(() => mobilityRepository.getMyTrips(any())).thenThrow(
        const PostgrestException(
          message: 'column mobility_trips.country does not exist',
          code: '42703',
        ),
      );

      await notifier.loadDriverProfile();

      expect(notifier.state.error, isNull);
      expect(notifier.state.profile, isNotNull);
      expect(notifier.state.profile!.fullName, 'Legacy Driver');
      expect(notifier.state.profile!.vehicleType, 'Moto');
      expect(notifier.state.subscription, isNotNull);
      expect(notifier.state.subscription!.isSubscribed, isFalse);
      expect(notifier.state.scheduledTrips, isEmpty);
    },
  );
}
