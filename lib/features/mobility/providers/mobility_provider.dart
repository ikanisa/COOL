import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/hive_providers.dart';

import '../../../core/auth/auth_user_contact.dart';
import '../../../core/config/app_market.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/services/app_review_service.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/engagement_tracker.dart';
import '../../../core/services/performance_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/driver_info.dart';
import '../models/trip_type.dart';
import '../repositories/mobility_repository.dart';
import '../repositories/trip_repository.dart';

final mobilityRepositoryProvider = Provider<MobilityRepository>((ref) {
  return MobilityRepository(client: ref.read(supabaseClientProvider));
});

final mobilityTripRepositoryProvider = Provider<TripRepository>((ref) {
  return TripRepository(
    client: ref.read(supabaseClientProvider),
    openBox: ref.read(hiveOpenBoxProvider),
  );
});

final mobilityProvider = StateNotifierProvider<MobilityNotifier, MobilityState>(
  (ref) {
    final repository = ref.watch(mobilityRepositoryProvider);
    final tripRepository = ref.watch(mobilityTripRepositoryProvider);
    final authState = ref.watch(authProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);
    final engagement = ref.read(engagementTrackerProvider);
    final performance = ref.read(performanceServiceProvider);
    final appReview = ref.read(appReviewServiceProvider);
    return MobilityNotifier(
      repository: repository,
      tripRepository: tripRepository,
      authState: authState,
      crashlytics: crashlytics,
      engagement: engagement,
      performance: performance,
      appReview: appReview,
    );
  },
);

final mobilitySubmissionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.isSubmittingTrip));
});

final mobilitySubmissionErrorProvider = Provider<String?>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.submissionError));
});

class MobilityState {
  const MobilityState({
    this.isDriverOnline = false,
    this.isSubmittingTrip = false,
    this.isUpdatingDriverStatus = false,
    this.submissionError,
  });

  final bool isDriverOnline;
  final bool isSubmittingTrip;
  final bool isUpdatingDriverStatus;
  final String? submissionError;

  MobilityState copyWith({
    bool? isDriverOnline,
    bool? isSubmittingTrip,
    bool? isUpdatingDriverStatus,
    Object? submissionError = const Object(),
  }) {
    return MobilityState(
      isDriverOnline: isDriverOnline ?? this.isDriverOnline,
      isSubmittingTrip: isSubmittingTrip ?? this.isSubmittingTrip,
      isUpdatingDriverStatus:
          isUpdatingDriverStatus ?? this.isUpdatingDriverStatus,
      submissionError: submissionError == const Object()
          ? this.submissionError
          : submissionError as String?,
    );
  }
}

class MobilityNotifier extends StateNotifier<MobilityState> {
  MobilityNotifier({
    required MobilityRepository repository,
    required TripRepository tripRepository,
    required AuthState authState,
    required CrashlyticsService crashlytics,
    required EngagementTracker engagement,
    required PerformanceService performance,
    required AppReviewService appReview,
  }) : _repository = repository,
       _tripRepository = tripRepository,
       _authState = authState,
       _crashlytics = crashlytics,
       _engagement = engagement,
       _performance = performance,
       _appReview = appReview,
       super(const MobilityState());

  final MobilityRepository _repository;
  final TripRepository _tripRepository;
  final AuthState _authState;
  final CrashlyticsService _crashlytics;
  final EngagementTracker _engagement;
  final PerformanceService _performance;
  final AppReviewService _appReview;

  String? get _currentUserId =>
      _authState.user?.id ?? _authState.session?.user.id;

  Future<void> toggleDriverOnline(double latitude, double longitude) async {
    final userId = _currentUserId;

    if (userId == null) {
      state = state.copyWith(
        submissionError: 'A signed-in driver is required.',
      );
      return;
    }

    final nextValue = !state.isDriverOnline;
    state = state.copyWith(isUpdatingDriverStatus: true, submissionError: null);

    final result = await AsyncValue.guard(
      () => _repository.setDriverOnline(
        userId,
        nextValue,
        latitude,
        longitude,
      ),
    );

    result.when(
      data: (_) {
        _engagement.trackDriverWentOnline(
          isOnline: nextValue,
          vehicleType: _authState.user?.vehicleType ?? 'Any',
        );
        state = state.copyWith(
          isDriverOnline: nextValue,
          isUpdatingDriverStatus: false,
          submissionError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isUpdatingDriverStatus: false,
          submissionError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<TripPostResult?> createTrip(TripPostRequest data) async {
    final currentUser = _authState.user;
    final isDriverReturnTrip =
        data.isDriverReturnTrip ||
        (data.role?.trim().toUpperCase() == 'DRIVER');
    final request = data.copyWith(
      userId: data.userId ?? _currentUserId,
      role: data.role ?? (isDriverReturnTrip ? 'DRIVER' : 'PASSENGER'),
      contactPhone:
          data.contactPhone ??
          currentUser?.phone ??
          authSessionPhone(_authState.session),
      contactName: data.contactName ?? currentUser?.displayUserId,
      whatsappNumber:
          data.whatsappNumber ??
          data.contactPhone ??
          currentUser?.phone ??
          authSessionPhone(_authState.session),
      isDriverReturnTrip: isDriverReturnTrip,
    );

    state = state.copyWith(isSubmittingTrip: true, submissionError: null);
    _performance.startTrace('mobility_create_trip');

    final result = await AsyncValue.guard(
      () => _tripRepository.createTrip(request),
    );

    TripPostResult? createdTrip;

    result.when(
      data: (value) {
        createdTrip = value;
        _performance.stopTrace('mobility_create_trip');
        _engagement.trackTripScheduled(
          role: request.role ?? 'PASSENGER',
          vehicleType: _vehicleLabelForRequest(
            request,
            fallback: currentUser?.vehicleType,
          ),
          recurring: request.isRecurringTrip,
          returnTrip: request.isReturnTrip,
          storedOffline: value.storedOffline,
        );
        state = state.copyWith(
          isSubmittingTrip: false,
          submissionError: null,
        );
        unawaited(_appReview.requestReview());
      },
      error: (error, stack) {
        _performance.stopTrace('mobility_create_trip');
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'mobility_create_trip',
        );
        state = state.copyWith(
          isSubmittingTrip: false,
          submissionError: error.toString(),
        );
      },
      loading: () {},
    );

    return createdTrip;
  }

  String _vehicleLabelForRequest(TripPostRequest request, {String? fallback}) {
    switch (request.vehiclePreference) {
      case TripVehiclePreference.moto:
        return 'Moto';
      case TripVehiclePreference.cab:
        return 'Cab';
      case TripVehiclePreference.any:
        final normalized = fallback?.trim();
        return normalized == null || normalized.isEmpty ? 'Any' : normalized;
    }
  }
}

