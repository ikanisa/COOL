import 'dart:math' as math;

import 'package:equatable/equatable.dart';

class GeoPoint extends Equatable {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  double distanceToKm(GeoPoint other) {
    const earthRadiusKm = 6371.0;
    final deltaLat = _toRadians(other.latitude - latitude);
    final deltaLng = _toRadians(other.longitude - longitude);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(other.latitude)) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  @override
  List<Object> get props => <Object>[latitude, longitude];
}
