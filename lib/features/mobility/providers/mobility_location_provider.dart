import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box, Hive;

import '../../../core/providers/app_access_provider.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return DeviceLocationService.instance;
});

final mobilityLocationProvider =
    StateNotifierProvider<MobilityLocationNotifier, MobilityLocationState>((
      ref,
    ) {
      final service = ref.watch(locationServiceProvider);
      final appAccess = ref.watch(appAccessServiceProvider);
      return MobilityLocationNotifier(
        service: service,
        openBox: Hive.openBox<dynamic>,
        appAccessService: appAccess,
      );
    });

enum MobilityLocationStatus {
  idle,
  checking,
  accessDisabled,
  needsPermission,
  requesting,
  ready,
  approximateReady,
  denied,
  deniedForever,
  serviceDisabled,
  error,
}

class MobilityLocationState {
  const MobilityLocationState({
    this.status = MobilityLocationStatus.idle,
    this.position,
    this.updatedAt,
    this.accuracyMeters,
    this.isTracking = false,
    this.isStale = false,
    this.error,
  });

  static const _sentinel = Object();

  final MobilityLocationStatus status;
  final GeoPoint? position;
  final DateTime? updatedAt;
  final double? accuracyMeters;
  final bool isTracking;
  final bool isStale;
  final String? error;

  bool get hasLocation =>
      position != null &&
      (status == MobilityLocationStatus.ready ||
          status == MobilityLocationStatus.approximateReady);

  bool get isApproximate => status == MobilityLocationStatus.approximateReady;

  bool get isLoading =>
      status == MobilityLocationStatus.checking ||
      status == MobilityLocationStatus.requesting;

  MobilityLocationState copyWith({
    MobilityLocationStatus? status,
    Object? position = _sentinel,
    Object? updatedAt = _sentinel,
    Object? accuracyMeters = _sentinel,
    bool? isTracking,
    bool? isStale,
    Object? error = _sentinel,
  }) {
    return MobilityLocationState(
      status: status ?? this.status,
      position: position == _sentinel ? this.position : position as GeoPoint?,
      updatedAt: updatedAt == _sentinel
          ? this.updatedAt
          : updatedAt as DateTime?,
      accuracyMeters: accuracyMeters == _sentinel
          ? this.accuracyMeters
          : accuracyMeters as double?,
      isTracking: isTracking ?? this.isTracking,
      isStale: isStale ?? this.isStale,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

class MobilityLocationNotifier extends StateNotifier<MobilityLocationState> {
  MobilityLocationNotifier({
    required LocationService service,
    required Future<Box<dynamic>> Function(String name) openBox,
    required AppAccessService appAccessService,
  }) : _service = service,
       _openBox = openBox,
       _appAccessService = appAccessService,
       super(const MobilityLocationState());

  static const _cacheBoxName = 'mobility_location_cache';
  static const _cacheKey = 'latest_position';

  final LocationService _service;
  final Future<Box<dynamic>> Function(String name) _openBox;
  final AppAccessService _appAccessService;

  bool _permissionPromptShownThisSession = false;
  bool _mobilityBranchActive = false;
  int _trackingRetainers = 0;

  Future<void> bootstrap() async {
    await _resolveLocation(requestIfNeeded: false);
  }

  Future<void> requestForegroundAccess() async {
    await _appAccessService.setEnabled(AppAccessPermission.location, true);
    _permissionPromptShownThisSession = true;
    await _resolveLocation(requestIfNeeded: true);
  }

  Future<void> refresh() async {
    await _resolveLocation(requestIfNeeded: false);
  }

  Future<void> startTracking() async {
    _trackingRetainers = _trackingRetainers == 0 ? 1 : _trackingRetainers;
    _mobilityBranchActive = true;
    await _syncTrackingState();
  }

  Future<void> stopTracking() async {
    _trackingRetainers = 0;
    await _syncTrackingState();
  }

  Future<void> acquireTracking() async {
    _trackingRetainers += 1;
    await _syncTrackingState();
  }

  Future<void> releaseTracking() async {
    if (_trackingRetainers > 0) {
      _trackingRetainers -= 1;
    }
    await _syncTrackingState();
  }

  Future<void> setMobilityBranchActive(bool isActive) async {
    if (_mobilityBranchActive == isActive) {
      return;
    }

    _mobilityBranchActive = isActive;
    await _syncTrackingState();
  }

  Future<void> openAppSettings() async {
    await _service.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await _service.openLocationSettings();
  }

  Future<void> _resolveLocation({
    required bool requestIfNeeded,
    bool shouldStartTracking = false,
  }) async {
    state = state.copyWith(
      status: requestIfNeeded
          ? MobilityLocationStatus.requesting
          : MobilityLocationStatus.checking,
      error: null,
    );

    final appAccessEnabled = await _appAccessService.isEnabled(
      AppAccessPermission.location,
    );
    if (!appAccessEnabled) {
      await _service.stopLocationUpdates();
      state = state.copyWith(
        status: MobilityLocationStatus.accessDisabled,
        isTracking: false,
        error:
            'Location is turned off in COOL profile settings for mobility features.',
      );
      return;
    }

    final servicesEnabled = await _service.isLocationServiceEnabled();
    if (!servicesEnabled) {
      await _service.stopLocationUpdates();
      state = state.copyWith(
        status: MobilityLocationStatus.serviceDisabled,
        isTracking: false,
        error: 'Location services are turned off on this device.',
      );
      return;
    }

    var permission = await _service.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await _service.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      await _service.stopLocationUpdates();
      state = state.copyWith(
        status: _permissionPromptShownThisSession
            ? MobilityLocationStatus.denied
            : MobilityLocationStatus.needsPermission,
        isTracking: false,
        error: requestIfNeeded
            ? 'Location permission was denied.'
            : 'Location permission is required to show nearby trips and drivers.',
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      await _service.stopLocationUpdates();
      state = state.copyWith(
        status: MobilityLocationStatus.deniedForever,
        isTracking: false,
        error:
            'Location permission is permanently denied. Open settings to enable it.',
      );
      return;
    }

    final accuracyStatus = await _safeAccuracyStatus();
    final lastKnown = await _service.getLastKnownLocation();
    final cached = await _readCachedPosition();

    if (lastKnown != null) {
      _setResolvedPosition(
        position: lastKnown,
        accuracyStatus: accuracyStatus,
        isStale: true,
      );
    } else if (cached != null) {
      state = state.copyWith(
        status: cached.isApproximate
            ? MobilityLocationStatus.approximateReady
            : MobilityLocationStatus.ready,
        position: cached.position,
        updatedAt: cached.updatedAt,
        accuracyMeters: cached.accuracyMeters,
        isStale: true,
        error: null,
      );
    }

    try {
      final current = await _service.getCurrentLocation(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _setResolvedPosition(
        position: current,
        accuracyStatus: accuracyStatus,
        isStale: false,
      );
      await _cachePosition(
        position: current,
        isApproximate: accuracyStatus == LocationAccuracyStatus.reduced,
      );
    } on TimeoutException {
      if (!state.hasLocation) {
        state = state.copyWith(
          status: MobilityLocationStatus.error,
          error: 'Timed out while trying to detect your location.',
        );
      }
    } catch (error) {
      if (!state.hasLocation) {
        state = state.copyWith(
          status: MobilityLocationStatus.error,
          error: error.toString(),
        );
      }
    }

    if (shouldStartTracking || _shouldTrack) {
      if (!state.isTracking) {
        await _service.startLocationUpdates(_handleLocationUpdate);
      }
      state = state.copyWith(isTracking: true);
    } else {
      state = state.copyWith(isTracking: false);
    }
  }

  bool get _shouldTrack => _mobilityBranchActive && _trackingRetainers > 0;

  Future<void> _syncTrackingState() async {
    if (_shouldTrack) {
      await _resolveLocation(requestIfNeeded: false, shouldStartTracking: true);
      return;
    }

    if (state.isTracking) {
      await _service.stopLocationUpdates();
    }
    state = state.copyWith(isTracking: false);
  }

  Future<LocationAccuracyStatus> _safeAccuracyStatus() async {
    try {
      return await _service.getLocationAccuracy();
    } catch (_) {
      return LocationAccuracyStatus.unknown;
    }
  }

  void _handleLocationUpdate(Position position) {
    _safeAccuracyStatus().then((accuracyStatus) async {
      _setResolvedPosition(
        position: position,
        accuracyStatus: accuracyStatus,
        isStale: false,
      );
      await _cachePosition(
        position: position,
        isApproximate: accuracyStatus == LocationAccuracyStatus.reduced,
      );
    });
  }

  void _setResolvedPosition({
    required Position position,
    required LocationAccuracyStatus accuracyStatus,
    required bool isStale,
  }) {
    state = state.copyWith(
      status: accuracyStatus == LocationAccuracyStatus.reduced
          ? MobilityLocationStatus.approximateReady
          : MobilityLocationStatus.ready,
      position: GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      updatedAt: position.timestamp,
      accuracyMeters: position.accuracy,
      isStale: isStale,
      error: null,
    );
  }

  Future<void> _cachePosition({
    required Position position,
    required bool isApproximate,
  }) async {
    final box = await _openBox(_cacheBoxName);
    await box.put(_cacheKey, <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy_meters': position.accuracy,
      'updated_at': position.timestamp.toIso8601String(),
      'is_approximate': isApproximate,
    });
  }

  Future<_CachedMobilityPosition?> _readCachedPosition() async {
    final box = await _openBox(_cacheBoxName);
    final raw = box.get(_cacheKey);
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final latitude = _asDouble(map['latitude']);
    final longitude = _asDouble(map['longitude']);
    if (latitude == null || longitude == null) {
      return null;
    }

    return _CachedMobilityPosition(
      position: GeoPoint(latitude: latitude, longitude: longitude),
      accuracyMeters: _asDouble(map['accuracy_meters']),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
      isApproximate: map['is_approximate'] == true,
    );
  }

  double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  @override
  void dispose() {
    unawaited(_service.stopLocationUpdates());
    super.dispose();
  }
}

class _CachedMobilityPosition {
  const _CachedMobilityPosition({
    required this.position,
    this.accuracyMeters,
    this.updatedAt,
    required this.isApproximate,
  });

  final GeoPoint position;
  final double? accuracyMeters;
  final DateTime? updatedAt;
  final bool isApproximate;
}
