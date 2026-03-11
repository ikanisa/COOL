import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

abstract class LocationService {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<LocationAccuracyStatus> getLocationAccuracy();

  Future<Position?> getLastKnownLocation();

  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  });

  Future<void> startLocationUpdates(ValueChanged<Position> onUpdate);

  Future<void> stopLocationUpdates();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();

  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _toRadians(lat2 - lat1);
    final deltaLng = _toRadians(lng2 - lng1);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return calculateDistance(
          userPos.latitude,
          userPos.longitude,
          targetLat,
          targetLng,
        ) <=
        10;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}

class DeviceLocationService extends LocationService {
  DeviceLocationService();

  static final DeviceLocationService instance = DeviceLocationService();

  StreamSubscription<Position>? _locationSubscription;

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  @override
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() {
    return Geolocator.getLocationAccuracy();
  }

  @override
  Future<Position?> getLastKnownLocation() {
    return Geolocator.getLastKnownPosition();
  }

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) {
    final future = Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy),
    );
    if (timeLimit == null) {
      return future;
    }
    return future.timeout(timeLimit);
  }

  @override
  Future<void> startLocationUpdates(ValueChanged<Position> onUpdate) async {
    await stopLocationUpdates();

    final locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 15),
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    };

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(onUpdate);
  }

  @override
  Future<void> stopLocationUpdates() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  @override
  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }

  @override
  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  @override
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _deviceToRadians(lat2 - lat1);
    final deltaLng = _deviceToRadians(lng2 - lng1);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(_deviceToRadians(lat1)) *
            math.cos(_deviceToRadians(lat2)) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return calculateDistance(
          userPos.latitude,
          userPos.longitude,
          targetLat,
          targetLng,
        ) <=
        10;
  }

  double _deviceToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}
