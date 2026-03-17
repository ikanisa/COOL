enum TripVehiclePreference { moto, cab, trike, truck, others, any }

extension TripVehiclePreferenceX on TripVehiclePreference {
  String get value => switch (this) {
    TripVehiclePreference.moto => 'moto',
    TripVehiclePreference.cab => 'cab',
    TripVehiclePreference.trike => 'trike',
    TripVehiclePreference.truck => 'truck',
    TripVehiclePreference.others => 'others',
    TripVehiclePreference.any => 'any',
  };
}

enum TripWeekday { mon, tue, wed, thu, fri, sat, sun }

extension TripWeekdayX on TripWeekday {
  String get value => name;
}

class TripPostRequest {
  const TripPostRequest({
    required this.fromLocation,
    required this.toLocation,
    required this.departureAt,
    required this.vehiclePreference,
    required this.seatsNeeded,
    this.userId,
    this.clientRequestId,
    this.returnAt,
    this.recurringDays = const <TripWeekday>[],
    this.role,
    this.latitude,
    this.longitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.contactPhone,
    this.contactName,
    this.whatsappNumber,
    this.isDriverReturnTrip = false,
    this.priceNote,
  });

  final String fromLocation;
  final String toLocation;
  final DateTime departureAt;
  final String? userId;
  final String? clientRequestId;
  final DateTime? returnAt;
  final TripVehiclePreference vehiclePreference;
  final int seatsNeeded;
  final List<TripWeekday> recurringDays;
  final String? role;
  final double? latitude;
  final double? longitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String? contactPhone;
  final String? contactName;
  final String? whatsappNumber;
  final bool isDriverReturnTrip;
  final String? priceNote;

  bool get isReturnTrip => returnAt != null;
  bool get isRecurringTrip => recurringDays.isNotEmpty;

  Map<String, dynamic> toJson({bool includeContactFields = true}) {
    final payload = <String, dynamic>{
      'from_location': fromLocation,
      'to_location': toLocation,
      'travel_time': departureAt.toIso8601String(),
      'return_at': returnAt?.toIso8601String(),
      'expires_at': departureAt.add(const Duration(hours: 1)).toIso8601String(),
      'user_id': userId,
      'client_request_id': clientRequestId,
      'role': _normalizedRole(role, isDriverReturnTrip: isDriverReturnTrip),
      'vehicle_type': vehiclePreference.value == 'any'
          ? 'any'
          : vehiclePreference.value,
      'seats': seatsNeeded,
      'trip_type': isDriverReturnTrip ? 'driver_return' : 'passenger',
      'is_return_trip': isReturnTrip,
      'is_recurring_trip': isRecurringTrip,
      'is_driver_return_trip': isDriverReturnTrip,
      'repeat_days': recurringDays.map((day) => day.value).toList(),
      'status': 'open',
      'from_lat': latitude,
      'from_lng': longitude,
      'to_lat': destinationLatitude,
      'to_lng': destinationLongitude,
      if (includeContactFields) 'contact_phone': contactPhone,
      if (includeContactFields) 'contact_name': contactName,
      'whatsapp_number': whatsappNumber ?? contactPhone,
      'price_note': priceNote,
    };

    payload.removeWhere((_, value) => value == null);
    return payload;
  }

  // toLegacyJson() removed — single canonical schema via toJson().

  TripPostRequest copyWith({
    String? fromLocation,
    String? toLocation,
    DateTime? departureAt,
    Object? userId = _sentinel,
    Object? clientRequestId = _sentinel,
    Object? returnAt = _sentinel,
    TripVehiclePreference? vehiclePreference,
    int? seatsNeeded,
    List<TripWeekday>? recurringDays,
    Object? role = _sentinel,
    Object? latitude = _sentinel,
    Object? longitude = _sentinel,
    Object? destinationLatitude = _sentinel,
    Object? destinationLongitude = _sentinel,
    Object? contactPhone = _sentinel,
    Object? contactName = _sentinel,
    Object? whatsappNumber = _sentinel,
    bool? isDriverReturnTrip,
    Object? priceNote = _sentinel,
  }) {
    return TripPostRequest(
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,
      departureAt: departureAt ?? this.departureAt,
      userId: userId == _sentinel ? this.userId : userId as String?,
      clientRequestId: clientRequestId == _sentinel
          ? this.clientRequestId
          : clientRequestId as String?,
      returnAt: returnAt == _sentinel ? this.returnAt : returnAt as DateTime?,
      vehiclePreference: vehiclePreference ?? this.vehiclePreference,
      seatsNeeded: seatsNeeded ?? this.seatsNeeded,
      recurringDays: recurringDays ?? this.recurringDays,
      role: role == _sentinel ? this.role : role as String?,
      latitude: latitude == _sentinel ? this.latitude : latitude as double?,
      longitude: longitude == _sentinel ? this.longitude : longitude as double?,
      destinationLatitude: destinationLatitude == _sentinel
          ? this.destinationLatitude
          : destinationLatitude as double?,
      destinationLongitude: destinationLongitude == _sentinel
          ? this.destinationLongitude
          : destinationLongitude as double?,
      contactPhone: contactPhone == _sentinel
          ? this.contactPhone
          : contactPhone as String?,
      contactName: contactName == _sentinel
          ? this.contactName
          : contactName as String?,
      whatsappNumber: whatsappNumber == _sentinel
          ? this.whatsappNumber
          : whatsappNumber as String?,
      isDriverReturnTrip: isDriverReturnTrip ?? this.isDriverReturnTrip,
      priceNote: priceNote == _sentinel ? this.priceNote : priceNote as String?,
    );
  }

  static const _sentinel = Object();

  factory TripPostRequest.fromOfflineCache(Map<String, dynamic> data) {
    final departureRaw = data['travel_time'] ?? data['departure_at'];
    if (departureRaw == null) {
      throw const FormatException('Missing departure time for cached trip.');
    }

    return TripPostRequest(
      fromLocation: data['from_location']?.toString() ?? '',
      toLocation: data['to_location']?.toString() ?? '',
      departureAt: DateTime.parse(departureRaw.toString()),
      userId: data['user_id']?.toString(),
      clientRequestId:
          data['client_request_id']?.toString() ?? data['id']?.toString(),
      returnAt: _parseDateTime(data['return_at']),
      vehiclePreference: _parseVehiclePreference(
        data['vehicle_type'] ?? data['vehicle_preference'],
      ),
      seatsNeeded: _parseInt(data['seats'] ?? data['seats_needed']) ?? 1,
      recurringDays: _parseWeekdays(
        data['repeat_days'] ?? data['recurring_days'],
      ),
      role: data['role']?.toString(),
      latitude: _parseDouble(data['from_lat'] ?? data['latitude']),
      longitude: _parseDouble(data['from_lng'] ?? data['longitude']),
      destinationLatitude: _parseDouble(data['to_lat']),
      destinationLongitude: _parseDouble(data['to_lng']),
      contactPhone: data['contact_phone']?.toString(),
      contactName: data['contact_name']?.toString(),
      whatsappNumber: data['whatsapp_number']?.toString(),
      isDriverReturnTrip:
          data['is_driver_return_trip'] == true ||
          data['trip_type']?.toString() == 'driver_return',
      priceNote: data['price_note']?.toString(),
    );
  }
}

class TripPostResult {
  const TripPostResult({required this.id, required this.storedOffline});

  final String id;
  final bool storedOffline;
}

String _normalizedRole(String? role, {required bool isDriverReturnTrip}) {
  final normalized = role?.trim().toUpperCase();
  if (normalized != null && normalized.isNotEmpty) {
    return normalized;
  }
  return isDriverReturnTrip ? 'DRIVER' : 'PASSENGER';
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return null;
  }

  return DateTime.tryParse(raw);
}

double? _parseDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

int? _parseInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

TripVehiclePreference _parseVehiclePreference(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  switch (normalized) {
    case 'moto':
      return TripVehiclePreference.moto;
    case 'cab':
      return TripVehiclePreference.cab;
    case 'trike':
    case 'liffan':
      return TripVehiclePreference.trike;
    case 'truck':
      return TripVehiclePreference.truck;
    case 'others':
    case 'pickup':
      return TripVehiclePreference.others;
    default:
      return TripVehiclePreference.any;
  }
}

List<TripWeekday> _parseWeekdays(Object? value) {
  if (value is! Iterable) {
    return const <TripWeekday>[];
  }

  final parsed = <TripWeekday>[];
  for (final item in value) {
    final normalized = item.toString().trim().toLowerCase();
    for (final day in TripWeekday.values) {
      if (day.name == normalized) {
        parsed.add(day);
        break;
      }
    }
  }
  return parsed;
}
