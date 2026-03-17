import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/driver_info.dart';
import '../models/trip_type.dart';
import '../repositories/mobility_repository.dart';
import 'mobility_location_provider.dart';
import 'mobility_provider.dart';

class DiscoveryState {
  const DiscoveryState({
    this.nearbyDrivers = const <DriverInfo>[],
    this.nearbyTrips = const <Trip>[],
    this.selectedVehicle = 'All',
    this.selectedTab = 0,
    this.isDriversLoading = false,
    this.isTripsLoading = false,
    this.error,
  });

  final List<DriverInfo> nearbyDrivers;
  final List<Trip> nearbyTrips;
  final String selectedVehicle;
  /// 0 = Nearby Drivers, 1 = Trips
  final int selectedTab;
  final bool isDriversLoading;
  final bool isTripsLoading;
  final String? error;

  bool get isLoading => isDriversLoading || isTripsLoading;

  DiscoveryState copyWith({
    List<DriverInfo>? nearbyDrivers,
    List<Trip>? nearbyTrips,
    String? selectedVehicle,
    int? selectedTab,
    bool? isDriversLoading,
    bool? isTripsLoading,
    String? error,
  }) {
    return DiscoveryState(
      nearbyDrivers: nearbyDrivers ?? this.nearbyDrivers,
      nearbyTrips: nearbyTrips ?? this.nearbyTrips,
      selectedVehicle: selectedVehicle ?? this.selectedVehicle,
      selectedTab: selectedTab ?? this.selectedTab,
      isDriversLoading: isDriversLoading ?? this.isDriversLoading,
      isTripsLoading: isTripsLoading ?? this.isTripsLoading,
      error: error ?? this.error,
    );
  }
}

class DiscoveryNotifier extends StateNotifier<DiscoveryState> {
  DiscoveryNotifier({
    required MobilityRepository repository,
    required AuthState authState,
    required Ref ref,
  }) : _repository = repository,
       _authState = authState,
       _ref = ref,
       super(const DiscoveryState()) {
    // Proactively listen to location changes for automatic discovery updates
    _locationSubscription = _ref.listen<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
        if (next.hasLocation && next.position != null) {
          final previousPosition = previous?.position;
          final nextPosition = next.position!;
          
          final shouldReload = previousPosition == null ||
              previousPosition.distanceToKm(nextPosition) > 0.05; // 50m threshold

          if (shouldReload) {
            refresh();
          }
        }
      },
    );
  }

  final MobilityRepository _repository;
  final AuthState _authState;
  final Ref _ref;
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;

  String? get _currentUserId => _authState.user?.id ?? _authState.session?.user.id;
  String get _currentCountry => AppMarket.countryCode;

  @override
  void dispose() {
    _locationSubscription.close();
    super.dispose();
  }

  Future<void> refresh() async {
    await Future.wait([
      loadNearbyDrivers(),
      loadNearbyTrips(),
    ]);
  }

  Future<void> loadNearbyDrivers() async {
    final location = _ref.read(mobilityLocationProvider).position;
    if (location == null) return;

    state = state.copyWith(isDriversLoading: true, error: null);

    try {
      final drivers = await _repository.getNearbyDrivers(
        location.latitude,
        location.longitude,
        _vehicleQueryValue(state.selectedVehicle),
        _currentCountry,
      );
      state = state.copyWith(
        nearbyDrivers: drivers,
        isDriversLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isDriversLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadNearbyTrips() async {
    final location = _ref.read(mobilityLocationProvider).position;
    if (location == null) return;

    state = state.copyWith(isTripsLoading: true, error: null);

    try {
      // Logic for trips (combining passenger and driver return)
      // Note: In the consolidated discovery, we fetch active passenger trips by default
      final trips = await _repository.getScheduledTrips(
        location.latitude,
        location.longitude,
        _vehicleQueryValue(state.selectedVehicle),
        TripType.passenger,
        _currentCountry,
      );

      state = state.copyWith(
        nearbyTrips: trips.where((t) => t.userId != _currentUserId).toList(),
        isTripsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isTripsLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> setVehicleFilter(String type) async {
    if (state.selectedVehicle == type) return;
    state = state.copyWith(selectedVehicle: type);
    await refresh();
  }

  void setSelectedTab(int tab) {
    if (state.selectedTab == tab) return;
    state = state.copyWith(selectedTab: tab);
  }

  String? _vehicleQueryValue(String vehicle) {
    final normalized = vehicle.toLowerCase();
    if (normalized == 'all') return null;
    if (normalized.contains('moto')) return 'moto';
    if (normalized.contains('cab')) return 'cab';
    if (normalized.contains('truck')) return 'truck';
    if (normalized.contains('trike') || normalized.contains('van')) return 'trike';
    if (normalized.contains('others') || normalized.contains('pickup')) return 'others';
    return normalized.trim().isEmpty ? null : normalized.trim();
  }
}

final discoveryProvider = StateNotifierProvider<DiscoveryNotifier, DiscoveryState>((ref) {
  final repository = ref.watch(mobilityRepositoryProvider);
  final authState = ref.watch(authProvider);
  return DiscoveryNotifier(
    repository: repository,
    authState: authState,
    ref: ref,
  );
});

final nearbyDriversProvider = Provider<List<DriverInfo>>((ref) {
  return ref.watch(discoveryProvider.select((s) => s.nearbyDrivers));
});

final nearbyTripsProvider = Provider<List<Trip>>((ref) {
  return ref.watch(discoveryProvider.select((s) => s.nearbyTrips));
});
