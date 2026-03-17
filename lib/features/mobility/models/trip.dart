import '../../../core/identity/public_user_identity.dart';
import '../../../core/utils/json_helpers.dart' as jh;
import 'trip_type.dart';

class Trip {
  const Trip({
    this.id,
    this.userId,
    required this.fromLocation,
    required this.toLocation,
    required this.departureTime,
    required this.vehicleType,
    this.seats = 1,
    this.isReturn = false,
    this.isRecurring = false,
    this.isDriverReturnTrip = false,
    this.returnTime,
    this.expiresAt,
    this.latitude,
    this.longitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.distanceKm,
    this.status = 'ACTIVE',
    this.role,
    this.repeatDays = const <String>[],
    this.contactPhone,
    this.contactName,
    this.whatsappNumber,
    this.priceNote,
  });

  final String? id;
  final String? userId;
  final String fromLocation;
  final String toLocation;
  final DateTime departureTime;
  final String vehicleType;
  final int seats;
  final bool isReturn;
  final bool isRecurring;
  final bool isDriverReturnTrip;
  final DateTime? returnTime;
  final DateTime? expiresAt;
  final double? latitude;
  final double? longitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final double? distanceKm;
  final String status;
  final String? role;
  final List<String> repeatDays;
  final String? contactPhone;
  final String? contactName;
  final String? whatsappNumber;
  final String? priceNote;

  TripType get tripType =>
      isDriverReturnTrip ? TripType.driverReturn : TripType.passenger;

  bool get isActive {
    final normalized = status.trim().toLowerCase();
    return normalized == 'active' || normalized == 'open';
  }

  /// A trip is expired if its explicit `expiresAt` is past,
  /// or the departure was more than 24 h ago and it's still "open".
  bool get isExpired {
    final now = DateTime.now();
    if (expiresAt != null && now.isAfter(expiresAt!)) return true;
    if (isActive && now.difference(departureTime).inHours > 24) return true;
    return false;
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    final role = json['role']?.toString();
    final repeatDays = _asStringList(
      json['repeat_days'] ?? json['recurring_days'],
    );
    final profile = jh.asMapOrEmpty(json['profile']);
    final userId = json['user_id']?.toString();
    final contactPhone =
        json['contact_phone']?.toString() ??
        json['whatsapp_number']?.toString();

    return Trip(
      id: json['id']?.toString(),
      userId: userId,
      fromLocation: json['from_location']?.toString() ?? '',
      toLocation: json['to_location']?.toString() ?? '',
      departureTime:
          jh.parseDateTime(
            json['travel_time'] ??
                json['departure_at'] ??
                json['departure_time'],
          ) ??
          DateTime.now(),
      vehicleType:
          json['vehicle_type']?.toString() ??
          json['vehicle_preference']?.toString() ??
          '',
      seats: _asInt(json['seats'] ?? json['seats_needed']),
      isReturn: jh.asBool(json['is_return_trip']),
      isRecurring: jh.asBool(json['is_recurring_trip']) || repeatDays.isNotEmpty,
      isDriverReturnTrip:
          _isDriverRole(role) ||
          jh.asBool(json['is_driver_return_trip']) ||
          json['trip_type']?.toString() == 'driver_return',
      returnTime: jh.parseDateTime(json['return_at']),
      expiresAt: jh.parseDateTime(json['expires_at']),
      latitude: jh.asDouble(json['from_lat'] ?? json['latitude'] ?? json['lat']),
      longitude: jh.asDouble(
        json['from_lng'] ?? json['longitude'] ?? json['lng'],
      ),
      destinationLatitude: jh.asDouble(
        json['to_lat'] ?? json['destination_latitude'] ?? json['dropoff_lat'],
      ),
      destinationLongitude: jh.asDouble(
        json['to_lng'] ?? json['destination_longitude'] ?? json['dropoff_lng'],
      ),
      distanceKm: jh.asDouble(json['distance_km']),
      status: json['status']?.toString() ?? 'ACTIVE',
      role: role,
      repeatDays: repeatDays,
      contactPhone: contactPhone,
      contactName: PublicUserIdentity.resolve(
        publicUserId:
            json['contact_name']?.toString() ??
            profile['public_user_id']?.toString(),
        userId: userId,
        phone: contactPhone,
      ),
      whatsappNumber: json['whatsapp_number']?.toString(),
      priceNote: json['price_note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'from_location': fromLocation,
      'to_location': toLocation,
      'travel_time': departureTime.toIso8601String(),
      'vehicle_type': vehicleType,
      'seats': seats,
      'is_return_trip': isReturn,
      'is_recurring_trip': isRecurring,
      'is_driver_return_trip': isDriverReturnTrip,
      'return_at': returnTime?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'from_lat': latitude,
      'from_lng': longitude,
      'to_lat': destinationLatitude,
      'to_lng': destinationLongitude,
      'distance_km': distanceKm,
      'status': status,
      'role': role ?? (isDriverReturnTrip ? 'DRIVER' : 'PASSENGER'),
      'repeat_days': repeatDays,
      'trip_type': tripType.name,
      'whatsapp_number': whatsappNumber ?? contactPhone,
      'contact_phone': contactPhone,
      'contact_name': contactName,
      'price_note': priceNote,
    };

    data.removeWhere((_, value) => value == null);
    return data;
  }

  Map<String, dynamic> toInsertJson() {
    final data = <String, dynamic>{
      'user_id': userId,
      'role': role ?? (isDriverReturnTrip ? 'DRIVER' : 'PASSENGER'),
      'vehicle_type': vehicleType,
      'trip_type': tripType.name,
      'from_location': fromLocation,
      'from_lat': latitude,
      'from_lng': longitude,
      'to_location': toLocation,
      'to_lat': destinationLatitude,
      'to_lng': destinationLongitude,
      'travel_time': departureTime.toIso8601String(),
      'return_at': returnTime?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'seats': seats,
      'is_return_trip': isReturn,
      'is_recurring_trip': isRecurring,
      'is_driver_return_trip': isDriverReturnTrip,
      'repeat_days': repeatDays,
      'status': status,
      'contact_phone': contactPhone,
      'whatsapp_number': whatsappNumber ?? contactPhone,
      'price_note': priceNote,
    };
    data.removeWhere((_, value) => value == null);
    return data;
  }
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

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

// _asDouble, _asBool, _parseDateTime, _asMap consolidated into
// core/utils/json_helpers.dart (imported as jh).

bool _isDriverRole(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == 'driver' || normalized == 'driver_return';
}
