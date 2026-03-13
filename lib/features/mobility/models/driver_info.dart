import '../../../core/identity/public_user_identity.dart';

class DriverInfo {
  const DriverInfo({
    required this.driverId,
    required this.displayName,
    required this.vehicleType,
    required this.distanceKm,
    required this.isOnline,
    this.vehicleEmoji,
    this.rating,
    this.tripCount,
    this.scheduledRoute,
    this.hasReturnTrip = false,
    this.contactPhone,
    this.baseLocation,
    this.vehicleStatus,
    this.isRegularDriver = false,
    this.lastActiveAt,
    this.latitude,
    this.longitude,
  });

  final String driverId;
  final String displayName;
  final String vehicleType;
  final double distanceKm;
  final bool isOnline;
  final String? vehicleEmoji;
  final double? rating;
  final int? tripCount;
  final String? scheduledRoute;
  final bool hasReturnTrip;
  final String? contactPhone;
  final String? baseLocation;
  final String? vehicleStatus;
  final bool isRegularDriver;
  final DateTime? lastActiveAt;
  final double? latitude;
  final double? longitude;

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    final profile = _asMap(json['profile']);
    final driverId =
        json['driver_id']?.toString() ?? json['user_id']?.toString() ?? '';
    final displayName = PublicUserIdentity.resolve(
      publicUserId:
          profile['public_user_id']?.toString() ??
          json['driver_name']?.toString() ??
          json['public_user_id']?.toString(),
      userId: driverId,
      phone: json['contact_phone']?.toString() ?? profile['phone']?.toString(),
    );
    return DriverInfo(
      driverId: driverId,
      displayName: displayName,
      vehicleType: json['vehicle_type']?.toString() ?? '',
      distanceKm: _asDouble(json['distance_km']) ?? 0,
      isOnline: _asBool(json['is_online']),
      vehicleEmoji: json['vehicle_emoji']?.toString(),
      rating: _asDouble(json['rating']),
      tripCount: _asInt(json['trip_count']),
      scheduledRoute: json['scheduled_route']?.toString(),
      hasReturnTrip: _asBool(json['has_return_trip']),
      contactPhone:
          json['contact_phone']?.toString() ?? profile['phone']?.toString(),
      baseLocation: json['base_location']?.toString(),
      vehicleStatus: json['vehicle_status']?.toString(),
      isRegularDriver:
          _asBool(json['is_regular_driver']) ||
          (_asInt(json['credits']) ?? 0) > 0,
      lastActiveAt: _parseDateTime(
        json['location_updated_at'] ?? json['updated_at'],
      ),
      latitude: _asDouble(
        json['last_location_lat'] ?? json['latitude'] ?? json['lat'],
      ),
      longitude: _asDouble(
        json['last_location_lng'] ?? json['longitude'] ?? json['lng'],
      ),
    );
  }
}

int? _asInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
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
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
