import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/trip_type.dart';
import '../repositories/mobility_repository.dart';
import 'mobility_provider.dart';

enum TripBoardTab { passengerTrips, driverReturnTrips }

final tripBoardProvider =
    StateNotifierProvider<TripBoardNotifier, TripBoardState>((ref) {
      final repository = ref.watch(mobilityRepositoryProvider);
      final authState = ref.watch(authProvider);
      return TripBoardNotifier(repository: repository, authState: authState);
    });

final tripBoardPublicTripsProvider = Provider<List<Trip>>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.publicTrips));
});

final tripBoardMyTripsProvider = Provider<List<Trip>>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.myTrips));
});

final tripBoardSelectedVehicleProvider = Provider<String>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.selectedVehicle));
});

final tripBoardActiveTabProvider = Provider<TripBoardTab>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.activeTab));
});

final tripBoardPublicTripsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(
    tripBoardProvider.select((state) => state.isLoadingPublicTrips),
  );
});

final tripBoardMyTripsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.isLoadingMyTrips));
});

final tripBoardActionTripIdProvider = Provider<String?>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.actionTripId));
});

final tripBoardPublicErrorProvider = Provider<String?>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.publicTripsError));
});

final tripBoardMyTripsErrorProvider = Provider<String?>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.myTripsError));
});

final tripBoardMutationErrorProvider = Provider<String?>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.mutationError));
});

final tripBoardLocationProvider = Provider<GeoPoint?>((ref) {
  return ref.watch(tripBoardProvider.select((state) => state.location));
});

class TripBoardState {
  const TripBoardState({
    this.publicTrips = const <Trip>[],
    this.myTrips = const <Trip>[],
    this.location,
    this.selectedVehicle = 'All',
    this.activeTab = TripBoardTab.passengerTrips,
    this.isLoadingPublicTrips = false,
    this.isLoadingMyTrips = false,
    this.actionTripId,
    this.publicTripsError,
    this.myTripsError,
    this.mutationError,
  });

  static const _sentinel = Object();

  final List<Trip> publicTrips;
  final List<Trip> myTrips;
  final GeoPoint? location;
  final String selectedVehicle;
  final TripBoardTab activeTab;
  final bool isLoadingPublicTrips;
  final bool isLoadingMyTrips;
  final String? actionTripId;
  final String? publicTripsError;
  final String? myTripsError;
  final String? mutationError;

  bool get isLoading => isLoadingPublicTrips || isLoadingMyTrips;
  bool get isMutating => actionTripId != null;
  String? get error => mutationError ?? publicTripsError ?? myTripsError;

  TripBoardState copyWith({
    List<Trip>? publicTrips,
    List<Trip>? myTrips,
    Object? location = _sentinel,
    String? selectedVehicle,
    TripBoardTab? activeTab,
    bool? isLoadingPublicTrips,
    bool? isLoadingMyTrips,
    Object? actionTripId = _sentinel,
    Object? publicTripsError = _sentinel,
    Object? myTripsError = _sentinel,
    Object? mutationError = _sentinel,
  }) {
    return TripBoardState(
      publicTrips: publicTrips ?? this.publicTrips,
      myTrips: myTrips ?? this.myTrips,
      location: location == _sentinel ? this.location : location as GeoPoint?,
      selectedVehicle: selectedVehicle ?? this.selectedVehicle,
      activeTab: activeTab ?? this.activeTab,
      isLoadingPublicTrips: isLoadingPublicTrips ?? this.isLoadingPublicTrips,
      isLoadingMyTrips: isLoadingMyTrips ?? this.isLoadingMyTrips,
      actionTripId: actionTripId == _sentinel
          ? this.actionTripId
          : actionTripId as String?,
      publicTripsError: publicTripsError == _sentinel
          ? this.publicTripsError
          : publicTripsError as String?,
      myTripsError: myTripsError == _sentinel
          ? this.myTripsError
          : myTripsError as String?,
      mutationError: mutationError == _sentinel
          ? this.mutationError
          : mutationError as String?,
    );
  }
}

class TripBoardNotifier extends StateNotifier<TripBoardState> {
  TripBoardNotifier({
    required MobilityRepository repository,
    required AuthState authState,
  }) : _repository = repository,
       _authState = authState,
       super(const TripBoardState());

  final MobilityRepository _repository;
  final AuthState _authState;

  String? get _currentUserId =>
      _authState.user?.id ?? _authState.session?.user.id;
  String get _currentCountry => AppMarket.countryCode;

  void updateLocation(GeoPoint? location) {
    state = state.copyWith(
      location: location,
      publicTripsError: null,
      mutationError: null,
    );
  }

  void clearPublicTrips() {
    state = state.copyWith(publicTrips: const <Trip>[], publicTripsError: null);
  }

  Future<void> refresh() async {
    await Future.wait<void>(<Future<void>>[loadMyTrips(), loadPublicTrips()]);
  }

  Future<void> loadPublicTrips() async {
    final location = state.location;
    if (location == null) {
      state = state.copyWith(
        publicTrips: const <Trip>[],
        isLoadingPublicTrips: false,
        publicTripsError: null,
      );
      return;
    }

    state = state.copyWith(isLoadingPublicTrips: true, publicTripsError: null);

    final result = await AsyncValue.guard(
      () => _repository.getScheduledTrips(
        location.latitude,
        location.longitude,
        _vehicleQueryValue(state.selectedVehicle),
        state.activeTab == TripBoardTab.driverReturnTrips
            ? TripType.driverReturn
            : TripType.passenger,
        _currentCountry,
      ),
    );

    result.when(
      data: (trips) {
        state = state.copyWith(
          publicTrips: trips
              .where(
                (trip) => trip.userId != null && trip.userId != _currentUserId,
              )
              .toList(growable: false),
          isLoadingPublicTrips: false,
          publicTripsError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isLoadingPublicTrips: false,
          publicTripsError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<void> loadMyTrips() async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        myTrips: const <Trip>[],
        isLoadingMyTrips: false,
        myTripsError: null,
      );
      return;
    }

    state = state.copyWith(isLoadingMyTrips: true, myTripsError: null);

    final result = await AsyncValue.guard(
      () => _repository.getMyTrips(userId),
    );

    result.when(
      data: (trips) {
        state = state.copyWith(
          myTrips: trips,
          isLoadingMyTrips: false,
          myTripsError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isLoadingMyTrips: false,
          myTripsError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<void> setVehicleFilter(String type) async {
    state = state.copyWith(selectedVehicle: type, publicTripsError: null);
    await loadPublicTrips();
  }

  Future<void> setActiveTab(TripBoardTab tab) async {
    state = state.copyWith(activeTab: tab, publicTripsError: null);
    await loadPublicTrips();
  }

  Future<bool> cancelTrip(String tripId) async {
    state = state.copyWith(actionTripId: tripId, mutationError: null);

    final result = await AsyncValue.guard(() => _repository.cancelTrip(tripId));

    var succeeded = false;
    await result.when(
      data: (_) async {
        succeeded = true;
        await refresh();
      },
      error: (error, _) async {
        state = state.copyWith(mutationError: error.toString());
      },
      loading: () async {},
    );

    state = state.copyWith(actionTripId: null);
    return succeeded;
  }

  Future<bool> pauseTrip(String tripId) async {
    state = state.copyWith(actionTripId: tripId, mutationError: null);

    final result = await AsyncValue.guard(() => _repository.pauseTrip(tripId));

    var succeeded = false;
    await result.when(
      data: (_) async {
        succeeded = true;
        await refresh();
      },
      error: (error, _) async {
        state = state.copyWith(mutationError: error.toString());
      },
      loading: () async {},
    );

    state = state.copyWith(actionTripId: null);
    return succeeded;
  }

  Future<bool> repostTrip(String tripId) async {
    state = state.copyWith(actionTripId: tripId, mutationError: null);

    final result = await AsyncValue.guard(() => _repository.repostTrip(tripId));

    var succeeded = false;
    await result.when(
      data: (_) async {
        succeeded = true;
        await refresh();
      },
      error: (error, _) async {
        state = state.copyWith(mutationError: error.toString());
      },
      loading: () async {},
    );

    state = state.copyWith(actionTripId: null);
    return succeeded;
  }

  Future<bool> deleteTrip(String tripId) async {
    state = state.copyWith(actionTripId: tripId, mutationError: null);

    final result = await AsyncValue.guard(() => _repository.deleteTrip(tripId));

    var succeeded = false;
    await result.when(
      data: (_) async {
        succeeded = true;
        state = state.copyWith(
          myTrips: state.myTrips
              .where((trip) => trip.id != tripId)
              .toList(growable: false),
          publicTrips: state.publicTrips
              .where((trip) => trip.id != tripId)
              .toList(growable: false),
          mutationError: null,
        );
      },
      error: (error, _) async {
        state = state.copyWith(mutationError: error.toString());
      },
      loading: () async {},
    );

    state = state.copyWith(actionTripId: null);
    return succeeded;
  }

  String? _vehicleQueryValue(String vehicle) {
    final normalized = vehicle.toLowerCase();
    if (normalized == 'all') {
      return null;
    }
    if (normalized.contains('moto')) {
      return 'moto';
    }
    if (normalized.contains('cab')) {
      return 'cab';
    }
    if (normalized.contains('truck')) {
      return 'truck';
    }
    if (normalized.contains('liffan')) {
      return 'liffan';
    }
    return normalized.trim().isEmpty ? null : normalized.trim();
  }
}
