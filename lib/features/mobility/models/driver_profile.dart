class DriverProfile {
  const DriverProfile({
    required this.userId,
    required this.fullName,
    required this.vehicleType,
    this.vehicleDescription = '',
    this.isRegularDriver = false,
    required this.isOnline,
    this.avatarUrl,
    this.credits = 0,
    this.lastLocationLat,
    this.lastLocationLng,
    this.locationUpdatedAt,
    this.plateNumber = '',
    this.baseLocation = '',
    this.vehicleStatus = 'pending_review',
    this.rating = 0,
    this.tripsDone = 0,
  });

  final String userId;
  final String fullName;
  final String vehicleType;
  final String vehicleDescription;
  final bool isRegularDriver;
  final int credits;
  final double? lastLocationLat;
  final double? lastLocationLng;
  final DateTime? locationUpdatedAt;
  final String plateNumber;
  final String baseLocation;
  final String vehicleStatus;
  final bool isOnline;
  final String? avatarUrl;
  final double rating;
  final int tripsDone;

  DriverProfile copyWith({
    String? userId,
    String? fullName,
    String? vehicleType,
    String? vehicleDescription,
    bool? isRegularDriver,
    int? credits,
    Object? lastLocationLat = _sentinel,
    Object? lastLocationLng = _sentinel,
    Object? locationUpdatedAt = _sentinel,
    String? plateNumber,
    String? baseLocation,
    String? vehicleStatus,
    bool? isOnline,
    Object? avatarUrl = _sentinel,
    double? rating,
    int? tripsDone,
  }) {
    return DriverProfile(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleDescription: vehicleDescription ?? this.vehicleDescription,
      isRegularDriver: isRegularDriver ?? this.isRegularDriver,
      isOnline: isOnline ?? this.isOnline,
      avatarUrl: avatarUrl == _sentinel ? this.avatarUrl : avatarUrl as String?,
      credits: credits ?? this.credits,
      lastLocationLat: lastLocationLat == _sentinel
          ? this.lastLocationLat
          : lastLocationLat as double?,
      lastLocationLng: lastLocationLng == _sentinel
          ? this.lastLocationLng
          : lastLocationLng as double?,
      locationUpdatedAt: locationUpdatedAt == _sentinel
          ? this.locationUpdatedAt
          : locationUpdatedAt as DateTime?,
      plateNumber: plateNumber ?? this.plateNumber,
      baseLocation: baseLocation ?? this.baseLocation,
      vehicleStatus: vehicleStatus ?? this.vehicleStatus,
      rating: rating ?? this.rating,
      tripsDone: tripsDone ?? this.tripsDone,
    );
  }

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final userMap = _asMap(json['users']);
    final profileMap = _asMap(json['profile']);
    final tripsDone = _asInt(json['trips_done'] ?? json['trip_count']);
    final tripsUsedThisMonth = _asInt(json['trips_used_this_month']);
    final vehicleDescription =
        json['vehicle_description']?.toString() ??
        json['plate_number']?.toString() ??
        '';
    final isRegularDriver =
        _asBool(json['is_regular_driver']) || tripsDone >= 15;
    final credits = _asInt(json['credits']);

    return DriverProfile(
      userId: json['user_id']?.toString() ?? '',
      fullName:
          userMap['full_name']?.toString() ??
          profileMap['full_name']?.toString() ??
          userMap['name']?.toString() ??
          profileMap['name']?.toString() ??
          json['full_name']?.toString() ??
          'Driver',
      vehicleType: json['vehicle_type']?.toString() ?? 'Moto Taxi',
      vehicleDescription: vehicleDescription,
      isRegularDriver: isRegularDriver,
      vehicleStatus:
          json['vehicle_status']?.toString() ??
          json['status']?.toString() ??
          (isRegularDriver ? 'approved' : 'pending_review'),
      isOnline: _asBool(json['is_online']),
      avatarUrl:
          userMap['avatar_url']?.toString() ??
          profileMap['avatar_url']?.toString(),
      credits: credits > 0 ? credits : _remainingFreeTrips(tripsUsedThisMonth),
      lastLocationLat: _asDouble(
        json['last_location_lat'] ?? json['latitude'] ?? json['lat'],
      ),
      lastLocationLng: _asDouble(
        json['last_location_lng'] ?? json['longitude'] ?? json['lng'],
      ),
      locationUpdatedAt: _parseDateTime(
        json['location_updated_at'] ?? json['updated_at'],
      ),
      plateNumber: json['plate_number']?.toString() ?? vehicleDescription,
      baseLocation: json['base_location']?.toString() ?? '',
      rating: _asDouble(json['rating']),
      tripsDone: tripsDone,
    );
  }
}

int _remainingFreeTrips(int tripsUsedThisMonth) {
  const monthlyFreeTripQuota = 15;
  final remaining = monthlyFreeTripQuota - tripsUsedThisMonth;
  return remaining > 0 ? remaining : 0;
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

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double _asDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
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

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

const _sentinel = Object();
