import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_user_contact.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
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
  return TripRepository(client: ref.read(supabaseClientProvider));
});

final mobilityProvider = StateNotifierProvider<MobilityNotifier, MobilityState>(
  (ref) {
    final repository = ref.watch(mobilityRepositoryProvider);
    final tripRepository = ref.watch(mobilityTripRepositoryProvider);
    final authState = ref.watch(authProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);
    final engagement = ref.read(engagementTrackerProvider);
    final performance = ref.read(performanceServiceProvider);
    return MobilityNotifier(
      repository: repository,
      tripRepository: tripRepository,
      authState: authState,
      crashlytics: crashlytics,
      engagement: engagement,
      performance: performance,
    );
  },
);

final mobilityNearbyDriversProvider = Provider<List<DriverInfo>>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.nearbyDrivers));
});

final mobilityScheduledTripsProvider = Provider<List<Trip>>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.scheduledTrips));
});

final mobilitySelectedVehicleProvider = Provider<String>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.selectedVehicle));
});

final mobilityActiveTabProvider = Provider<int>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.activeTab));
});

final mobilityDiscoveryLoadingProvider = Provider<bool>((ref) {
  return ref.watch(
    mobilityProvider.select((state) => state.isDiscoveryLoading),
  );
});

final mobilityDiscoveryErrorProvider = Provider<String?>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.discoveryError));
});

final mobilitySubmissionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.isSubmittingTrip));
});

final mobilitySubmissionErrorProvider = Provider<String?>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.submissionError));
});

final mobilityUserLocationProvider = Provider<GeoPoint?>((ref) {
  return ref.watch(mobilityProvider.select((state) => state.userLocation));
});

class MobilityState {
  const MobilityState({
    this.nearbyDrivers = const <DriverInfo>[],
    this.scheduledTrips = const <Trip>[],
    this.isDriverOnline = false,
    this.userLocation,
    this.selectedVehicle = 'All',
    this.activeTab = 0,
    this.isLoadingNearbyDrivers = false,
    this.isLoadingScheduledTrips = false,
    this.isSubmittingTrip = false,
    this.isUpdatingDriverStatus = false,
    this.discoveryError,
    this.submissionError,
  });

  static const _sentinel = Object();

  final List<DriverInfo> nearbyDrivers;
  final List<Trip> scheduledTrips;
  final bool isDriverOnline;
  final GeoPoint? userLocation;
  final String selectedVehicle;
  final int activeTab;
  final bool isLoadingNearbyDrivers;
  final bool isLoadingScheduledTrips;
  final bool isSubmittingTrip;
  final bool isUpdatingDriverStatus;
  final String? discoveryError;
  final String? submissionError;

  bool get isDiscoveryLoading =>
      isLoadingNearbyDrivers || isLoadingScheduledTrips;

  bool get isLoading => isSubmittingTrip;

  String? get error => submissionError ?? discoveryError;

  MobilityState copyWith({
    List<DriverInfo>? nearbyDrivers,
    List<Trip>? scheduledTrips,
    bool? isDriverOnline,
    Object? userLocation = _sentinel,
    String? selectedVehicle,
    int? activeTab,
    bool? isLoadingNearbyDrivers,
    bool? isLoadingScheduledTrips,
    bool? isSubmittingTrip,
    bool? isUpdatingDriverStatus,
    Object? discoveryError = _sentinel,
    Object? submissionError = _sentinel,
  }) {
    return MobilityState(
      nearbyDrivers: nearbyDrivers ?? this.nearbyDrivers,
      scheduledTrips: scheduledTrips ?? this.scheduledTrips,
      isDriverOnline: isDriverOnline ?? this.isDriverOnline,
      userLocation: userLocation == _sentinel
          ? this.userLocation
          : userLocation as GeoPoint?,
      selectedVehicle: selectedVehicle ?? this.selectedVehicle,
      activeTab: activeTab ?? this.activeTab,
      isLoadingNearbyDrivers:
          isLoadingNearbyDrivers ?? this.isLoadingNearbyDrivers,
      isLoadingScheduledTrips:
          isLoadingScheduledTrips ?? this.isLoadingScheduledTrips,
      isSubmittingTrip: isSubmittingTrip ?? this.isSubmittingTrip,
      isUpdatingDriverStatus:
          isUpdatingDriverStatus ?? this.isUpdatingDriverStatus,
      discoveryError: discoveryError == _sentinel
          ? this.discoveryError
          : discoveryError as String?,
      submissionError: submissionError == _sentinel
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
  }) : _repository = repository,
       _tripRepository = tripRepository,
       _authState = authState,
       _crashlytics = crashlytics,
       _engagement = engagement,
       _performance = performance,
       super(const MobilityState());

  final MobilityRepository _repository;
  final TripRepository _tripRepository;
  final AuthState _authState;
  final CrashlyticsService _crashlytics;
  final EngagementTracker _engagement;
  final PerformanceService _performance;

  String? get _currentUserId =>
      _authState.user?.id ?? _authState.session?.user.id;
  String get _currentCountry => resolveAuthStateCountryCode(_authState);

  Future<void> loadNearbyDrivers() async {
    final location = state.userLocation;
    if (location == null) {
      state = state.copyWith(
        nearbyDrivers: const <DriverInfo>[],
        isLoadingNearbyDrivers: false,
        discoveryError: null,
      );
      return;
    }

    state = state.copyWith(isLoadingNearbyDrivers: true, discoveryError: null);
    _performance.startTrace('mobility_nearby_drivers');
    _crashlytics.log('mobility: loading nearby drivers');

    final result = await AsyncValue.guard(
      () => _repository.getNearbyDrivers(
        location.latitude,
        location.longitude,
        _vehicleQueryValue(state.selectedVehicle),
        _currentCountry,
      ),
    );

    result.when(
      data: (drivers) {
        _performance.stopTrace(
          'mobility_nearby_drivers',
          metrics: {'count': drivers.length},
        );
        state = state.copyWith(
          nearbyDrivers: drivers,
          isLoadingNearbyDrivers: false,
          discoveryError: null,
        );
      },
      error: (error, stack) {
        _performance.stopTrace(
          'mobility_nearby_drivers',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'mobility_nearby_drivers',
        );
        state = state.copyWith(
          isLoadingNearbyDrivers: false,
          discoveryError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<void> loadScheduledTrips() async {
    final location = state.userLocation;
    if (location == null) {
      state = state.copyWith(
        scheduledTrips: const <Trip>[],
        isLoadingScheduledTrips: false,
        discoveryError: null,
      );
      return;
    }

    state = state.copyWith(isLoadingScheduledTrips: true, discoveryError: null);
    _performance.startTrace('mobility_scheduled_trips');

    final result = await AsyncValue.guard(
      () => _repository.getScheduledTrips(
        location.latitude,
        location.longitude,
        _vehicleQueryValue(state.selectedVehicle),
        state.activeTab == 1 ? TripType.driverReturn : TripType.passenger,
        _currentCountry,
      ),
    );

    result.when(
      data: (trips) {
        _performance.stopTrace(
          'mobility_scheduled_trips',
          metrics: {'count': trips.length},
        );
        state = state.copyWith(
          scheduledTrips: trips,
          isLoadingScheduledTrips: false,
          discoveryError: null,
        );
      },
      error: (error, stack) {
        _performance.stopTrace(
          'mobility_scheduled_trips',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'mobility_scheduled_trips',
        );
        state = state.copyWith(
          isLoadingScheduledTrips: false,
          discoveryError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<void> toggleDriverOnline() async {
    final userId = _currentUserId;
    final location = state.userLocation;

    if (userId == null || location == null) {
      state = state.copyWith(
        discoveryError: 'A signed-in driver with a location is required.',
      );
      return;
    }

    final nextValue = !state.isDriverOnline;
    state = state.copyWith(isUpdatingDriverStatus: true, discoveryError: null);

    final result = await AsyncValue.guard(
      () => _repository.setDriverOnline(
        userId,
        nextValue,
        location.latitude,
        location.longitude,
      ),
    );

    result.when(
      data: (_) {
        final vehicleType =
            _authState.user?.vehicleType?.trim().toLowerCase().isNotEmpty ==
                true
            ? _authState.user!.vehicleType!.trim()
            : state.selectedVehicle;
        _engagement.trackDriverWentOnline(
          isOnline: nextValue,
          vehicleType: vehicleType,
        );
        state = state.copyWith(
          isDriverOnline: nextValue,
          isUpdatingDriverStatus: false,
          discoveryError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isUpdatingDriverStatus: false,
          discoveryError: error.toString(),
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
      latitude: data.latitude ?? state.userLocation?.latitude,
      longitude: data.longitude ?? state.userLocation?.longitude,
      contactPhone:
          data.contactPhone ??
          currentUser?.phone ??
          authSessionPhone(_authState.session),
      contactName: data.contactName ?? currentUser?.fullName,
      whatsappNumber:
          data.whatsappNumber ??
          data.contactPhone ??
          currentUser?.phone ??
          authSessionPhone(_authState.session),
      isDriverReturnTrip: isDriverReturnTrip,
    );

    state = state.copyWith(isSubmittingTrip: true, submissionError: null);
    _performance.startTrace('mobility_create_trip');
    _crashlytics.log(
      'mobility: creating trip ${request.fromLocation} → ${request.toLocation}',
    );

    final result = await AsyncValue.guard(
      () => _tripRepository.createTrip(request),
    );

    TripPostResult? createdTrip;

    result.when(
      data: (value) {
        createdTrip = value;
        _performance.stopTrace('mobility_create_trip');
        _crashlytics.log('mobility: trip created id=${value.id}');
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
          scheduledTrips: <Trip>[
            Trip(
              id: value.id,
              userId: request.userId,
              fromLocation: request.fromLocation,
              toLocation: request.toLocation,
              departureTime: request.departureAt,
              vehicleType: _vehicleLabelForRequest(
                request,
                fallback: currentUser?.vehicleType,
              ),
              seats: request.seatsNeeded,
              status: 'ACTIVE',
              isReturn: request.isReturnTrip,
              isRecurring: request.isRecurringTrip,
              isDriverReturnTrip: request.isDriverReturnTrip,
              returnTime: request.returnAt,
              latitude: request.latitude,
              longitude: request.longitude,
              destinationLatitude: request.destinationLatitude,
              destinationLongitude: request.destinationLongitude,
              role: request.role,
              repeatDays: request.recurringDays
                  .map((day) => day.value)
                  .toList(growable: false),
              contactPhone: request.contactPhone,
              contactName: request.contactName,
              whatsappNumber: request.whatsappNumber,
            ),
            ...state.scheduledTrips,
          ],
          isSubmittingTrip: false,
          submissionError: null,
        );
      },
      error: (error, stack) {
        _performance.stopTrace(
          'mobility_create_trip',
          attributes: {'error': error.runtimeType.toString()},
        );
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

  Future<void> setVehicleFilter(String type) async {
    state = state.copyWith(selectedVehicle: type, discoveryError: null);
    await loadNearbyDrivers();
    await loadScheduledTrips();
  }

  void updateLocation(GeoPoint location) {
    state = state.copyWith(userLocation: location, discoveryError: null);
  }

  void clearLocation() {
    state = state.copyWith(
      userLocation: null,
      nearbyDrivers: const <DriverInfo>[],
      scheduledTrips: const <Trip>[],
      discoveryError: null,
    );
  }

  Future<void> setActiveTab(int tab) async {
    if (state.activeTab == tab) {
      return;
    }

    _engagement.trackDiscoverTabSwitch(
      fromTab: _tabLabel(state.activeTab),
      toTab: _tabLabel(tab),
    );
    state = state.copyWith(activeTab: tab, discoveryError: null);
    await loadScheduledTrips();
  }

  String? _vehicleQueryValue(String vehicle) {
    final normalized = vehicle.toLowerCase();
    if (normalized == 'all') return null;
    if (normalized.contains('moto')) return 'moto';
    if (normalized.contains('cab')) return 'cab';
    if (normalized.contains('truck')) return 'truck';
    if (normalized.contains('liffan')) return 'liffan';
    return normalized.trim().isEmpty ? null : normalized.trim();
  }

  String _tabLabel(int tab) {
    switch (tab) {
      case 0:
        return 'scheduled';
      case 1:
        return 'return';
      case 2:
        return 'passenger';
      default:
        return 'tab_$tab';
    }
  }
}
