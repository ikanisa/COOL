import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/features/mobility/models/driver_profile.dart';
import 'package:cool_app/features/mobility/models/subscription_status.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../auth/providers/auth_provider.dart';
import '../repositories/mobility_repository.dart';
import '../repositories/subscription_repository.dart';
import '../../../core/providers/supabase_client_provider.dart';
import 'mobility_provider.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(client: ref.read(supabaseClientProvider));
});

final driverProvider = StateNotifierProvider<DriverNotifier, DriverState>((
  ref,
) {
  final authState = ref.watch(authProvider);
  final mobilityRepository = ref.watch(mobilityRepositoryProvider);
  final subscriptionRepository = ref.watch(subscriptionRepositoryProvider);
  return DriverNotifier(
    authState: authState,
    mobilityRepository: mobilityRepository,
    subscriptionRepository: subscriptionRepository,
  );
});

class DriverState {
  const DriverState({
    this.profile,
    this.subscription,
    this.scheduledTrips = const <Trip>[],
    this.tripsUsed = 0,
    this.isLoading = false,
    this.error,
  });

  static const _sentinel = Object();

  final DriverProfile? profile;
  final SubscriptionStatus? subscription;
  final List<Trip> scheduledTrips;
  final int tripsUsed;
  final bool isLoading;
  final String? error;

  DriverState copyWith({
    Object? profile = _sentinel,
    Object? subscription = _sentinel,
    List<Trip>? scheduledTrips,
    int? tripsUsed,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return DriverState(
      profile: profile == _sentinel ? this.profile : profile as DriverProfile?,
      subscription: subscription == _sentinel
          ? this.subscription
          : subscription as SubscriptionStatus?,
      scheduledTrips: scheduledTrips ?? this.scheduledTrips,
      tripsUsed: tripsUsed ?? this.tripsUsed,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

class DriverNotifier extends StateNotifier<DriverState> {
  DriverNotifier({
    required AuthState authState,
    required MobilityRepository mobilityRepository,
    required SubscriptionRepository subscriptionRepository,
  }) : _authState = authState,
       _mobilityRepository = mobilityRepository,
       _subscriptionRepository = subscriptionRepository,
       super(const DriverState());

  final AuthState _authState;
  final MobilityRepository _mobilityRepository;
  final SubscriptionRepository _subscriptionRepository;

  String? get _currentUserId =>
      _authState.user?.id ?? _authState.session?.user.id;

  String? get _vehicleType =>
      state.profile?.vehicleType ?? _authState.user?.vehicleType;

  Future<void> loadDriverProfile() async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        error: 'You must be signed in to load the driver profile.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    DriverProfile? profile;
    SubscriptionStatus? subscription;
    List<Trip> trips = const <Trip>[];
    String? error;
    var usedLegacyProfileFallback = false;

    await Future.wait([
      () async {
        try {
          profile = await _mobilityRepository.getDriverProfile(userId);
        } catch (err) {
          if (_isRecoverableBackendContractError(err)) {
            profile ??= _buildLegacyDriverProfileFallback(userId);
            usedLegacyProfileFallback = profile != null;
            return;
          }
          error ??= err.toString();
        }
      }(),
      () async {
        try {
          subscription = await _subscriptionRepository.getSubscriptionStatus(
            userId,
          );
        } catch (err) {
          if (_isRecoverableBackendContractError(err)) {
            subscription ??= SubscriptionStatus.freeTier(
              driverId: userId,
              tripsUsed: 0,
            );
            return;
          }
          error ??= err.toString();
        }
      }(),
      () async {
        try {
          trips = await _mobilityRepository.getMyTrips(userId);
        } catch (err) {
          if (_isRecoverableBackendContractError(err)) {
            trips = const <Trip>[];
            return;
          }
          error ??= err.toString();
        }
      }(),
    ]);

    if (usedLegacyProfileFallback && profile != null && subscription != null) {
      profile = profile!.copyWith(credits: subscription!.tripsRemaining);
    }

    state = state.copyWith(
      profile: profile,
      subscription: subscription,
      scheduledTrips: trips,
      tripsUsed: subscription?.tripsUsed ?? state.tripsUsed,
      isLoading: false,
      error: error,
    );
  }

  Future<DriverProfile?> updateVehicle(
    String type,
    String plateNumber,
    String baseLocation,
  ) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        error: 'You must be signed in to update vehicle details.',
      );
      return null;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _mobilityRepository.updateVehicle(
        userId,
        type,
        plateNumber,
        baseLocation,
      ),
    );

    DriverProfile? profile;

    result.when(
      data: (value) {
        profile = value;
        state = state.copyWith(profile: value, isLoading: false, error: null);
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () {},
    );

    return profile;
  }

  Future<void> setOnlineStatus({
    required bool isOnline,
    required double latitude,
    required double longitude,
  }) async {
    final userId = _currentUserId;
    final vehicleType = _vehicleType;
    if (userId == null) {
      state = state.copyWith(
        error: 'You must be signed in to update driver availability.',
      );
      return;
    }
    if ((vehicleType ?? '').trim().isEmpty) {
      state = state.copyWith(
        error: 'Add a vehicle type before turning on driver mode.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _mobilityRepository.setDriverOnline(
        userId,
        isOnline,
        latitude,
        longitude,
        vehicleType: vehicleType,
        vehicleDescription: state.profile?.vehicleDescription,
      ),
    );

    await result.when(
      data: (_) async {
        final updatedProfile = await _mobilityRepository.getDriverProfile(
          userId,
        );
        state = state.copyWith(
          profile:
              updatedProfile ??
              state.profile?.copyWith(
                vehicleType: vehicleType,
                isOnline: isOnline,
                lastLocationLat: latitude,
                lastLocationLng: longitude,
                locationUpdatedAt: DateTime.now(),
              ),
          isLoading: false,
          error: null,
        );
      },
      error: (error, _) async {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () async {},
    );
  }

  Future<void> syncOnlineLocation({
    required double latitude,
    required double longitude,
  }) async {
    final userId = _currentUserId;
    final profile = state.profile;
    if (userId == null || profile == null || !profile.isOnline) {
      return;
    }

    try {
      await _mobilityRepository.setDriverOnline(
        userId,
        true,
        latitude,
        longitude,
        vehicleType: profile.vehicleType,
        vehicleDescription: profile.vehicleDescription,
      );
      state = state.copyWith(
        profile: profile.copyWith(
          lastLocationLat: latitude,
          lastLocationLng: longitude,
          locationUpdatedAt: DateTime.now(),
        ),
      );
    } catch (err) {
      state = state.copyWith(error: err.toString());
    }
  }

  Future<void> refreshTrips() async {
    final userId = _currentUserId;
    if (userId == null) {
      return;
    }

    final result = await AsyncValue.guard(
      () => _mobilityRepository.getMyTrips(userId),
    );
    result.when(
      data: (trips) {
        state = state.copyWith(scheduledTrips: trips, error: null);
      },
      error: (error, _) {
        state = state.copyWith(error: error.toString());
      },
      loading: () {},
    );
  }

  Future<void> initiateSubscription(SubscriptionPlan plan) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        error: 'You must be signed in to start a subscription.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _subscriptionRepository.initiateSubscription(userId, plan.id),
    );

    await result.when(
      data: (_) async {
        await checkSubscriptionStatus();
      },
      error: (error, _) async {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () async {},
    );
  }

  Future<void> checkSubscriptionStatus() async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        error: 'You must be signed in to check subscription status.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _subscriptionRepository.getSubscriptionStatus(userId),
    );

    result.when(
      data: (subscription) {
        state = state.copyWith(
          subscription: subscription,
          tripsUsed: subscription.tripsUsed,
          isLoading: false,
          error: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () {},
    );
  }

  DriverProfile? _buildLegacyDriverProfileFallback(String userId) {
    final user = _authState.user;
    final vehicleType = user?.vehicleType?.trim();
    final hasDriverContext =
        user?.isDriver == true || (vehicleType?.isNotEmpty ?? false);

    if (!hasDriverContext) {
      return null;
    }

    return DriverProfile(
      userId: userId,
      fullName: user?.fullName.isNotEmpty == true ? user!.fullName : 'Driver',
      vehicleType: vehicleType?.isNotEmpty == true ? vehicleType! : 'Moto Taxi',
      isOnline: false,
      credits: 15,
    );
  }
}

bool _isRecoverableBackendContractError(Object error) {
  if (error is! PostgrestException) {
    return false;
  }

  final normalized = [
    error.code,
    error.message,
    error.details,
    error.hint,
  ].whereType<String>().join(' ').toLowerCase();

  return error.code == 'PGRST202' ||
      error.code == 'PGRST205' ||
      error.code == '42703' ||
      error.code == '42P01' ||
      normalized.contains('does not exist') ||
      normalized.contains('could not find') ||
      normalized.contains('column') ||
      normalized.contains('relation');
}
