import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/engagement_tracker.dart';
import 'package:cool_app/core/services/feature_flags_service.dart';
import 'package:cool_app/core/services/firebase_bootstrap_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/core/services/app_review_service.dart';
import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/trip_repository.dart';

class MockMobilityRepository extends Mock implements MobilityRepository {}

class MockTripRepository extends Mock implements TripRepository {}

class MockFirebaseBootstrapService extends Mock
    implements FirebaseBootstrapService {}

class MockFeatureFlagsService extends Mock implements FeatureFlagsService {}

class MockAppReviewService extends Mock implements AppReviewService {}

final _fallbackTripRequest = TripPostRequest(
  fromLocation: 'Kigali Heights',
  toLocation: 'BK Arena',
  departureAt: DateTime(2026, 3, 11, 8),
  vehiclePreference: TripVehiclePreference.moto,
  seatsNeeded: 1,
);

void main() {
  late MockMobilityRepository mobilityRepository;
  late MockTripRepository tripRepository;
  late MockFirebaseBootstrapService mockBootstrap;
  late MockFeatureFlagsService mockFeatureFlags;
  late MockAppReviewService mockAppReview;
  late MobilityNotifier notifier;

  setUpAll(() {
    registerFallbackValue(_fallbackTripRequest);
  });

  setUp(() {
    mobilityRepository = MockMobilityRepository();
    tripRepository = MockTripRepository();
    mockBootstrap = MockFirebaseBootstrapService();
    mockFeatureFlags = MockFeatureFlagsService();
    mockAppReview = MockAppReviewService();

    when(() => mockBootstrap.initialize()).thenAnswer((_) async => false);
    when(() => mockFeatureFlags.current).thenReturn(
      EngagementFeatureFlags.defaults(),
    );
    when(() => mockAppReview.requestReview()).thenAnswer((_) async {});

    notifier = MobilityNotifier(
      repository: mobilityRepository,
      tripRepository: tripRepository,
      authState: const AuthState(
        user: UserProfile(
          id: 'user-1',
          phone: '+250788123456',
          fullName: 'Cool Driver',
          momoNumber: '0788123456',
          momoProvider: 'mtn_momo_rw',
          country: 'RW',
          languageCode: 'en',
          isDriver: true,
          vehicleType: 'Moto',
        ),
      ),
      crashlytics: CrashlyticsService(),
      engagement: EngagementTracker(
        bootstrapService: mockBootstrap,
        featureFlagsService: mockFeatureFlags,
      ),
      performance: PerformanceService(),
      appReview: mockAppReview,
    );
  });

  group('MobilityNotifier.createTrip', () {
    test('keeps offline posts as success without surfacing an error', () async {
      when(() => tripRepository.createTrip(any())).thenAnswer(
        (_) async =>
            const TripPostResult(id: 'local-trip-1', storedOffline: true),
      );

      final result = await notifier.createTrip(_fallbackTripRequest);

      expect(result, isNotNull);
      expect(result!.storedOffline, isTrue);
      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.scheduledTrips, hasLength(1));
      expect(notifier.state.scheduledTrips.first.id, 'local-trip-1');
    });

    test(
      'surfaces server-side failures instead of reporting success',
      () async {
        when(() => tripRepository.createTrip(any())).thenThrow(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        );

        final result = await notifier.createTrip(_fallbackTripRequest);

        expect(result, isNull);
        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.scheduledTrips, isEmpty);
        expect(notifier.state.error, contains('row-level security'));
      },
    );
  });
}
