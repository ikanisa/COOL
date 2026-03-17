import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:cool_app/features/mobility/repositories/trip_repository.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

final _futureDate = DateTime.now().add(const Duration(days: 7));

TripPostRequest _request({
  String? clientRequestId,
  DateTime? departureAt,
  String? userId,
  bool isDriverReturnTrip = false,
  String? role,
}) {
  return TripPostRequest(
    fromLocation: 'Kigali Heights',
    toLocation: 'BK Arena',
    departureAt: departureAt ?? _futureDate,
    vehiclePreference: TripVehiclePreference.moto,
    seatsNeeded: 1,
    userId: userId ?? 'user-1',
    clientRequestId: clientRequestId,
    isDriverReturnTrip: isDriverReturnTrip,
    role: role,
  );
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════════
  // TripPostRequest serialization (pure, no mocks needed)
  // ═════════════════════════════════════════════════════════════════════════════

  group('TripPostRequest.toJson', () {
    test('includes canonical column names', () {
      final req = _request(clientRequestId: 'req-json');
      final json = req.toJson();

      expect(json['from_location'], 'Kigali Heights');
      expect(json['to_location'], 'BK Arena');
      expect(json['travel_time'], isA<String>());
      expect(json['vehicle_type'], 'moto');
      expect(json['seats'], 1);
      expect(json['status'], 'open');
      expect(json['client_request_id'], 'req-json');
      expect(json['trip_type'], 'passenger');
    });

    test('removes null values from json', () {
      final req = _request();
      final json = req.toJson();

      // latitude / longitude are null by default, should not be in json.
      expect(json.containsKey('from_lat'), isFalse);
      expect(json.containsKey('from_lng'), isFalse);
      expect(json.containsKey('to_lat'), isFalse);
      expect(json.containsKey('to_lng'), isFalse);
    });

    test('includes coordinates when provided', () {
      final req = _request().copyWith(
        latitude: -1.95,
        longitude: 30.06,
        destinationLatitude: -2.35,
        destinationLongitude: 29.87,
      );
      final json = req.toJson();

      expect(json['from_lat'], -1.95);
      expect(json['from_lng'], 30.06);
      expect(json['to_lat'], -2.35);
      expect(json['to_lng'], 29.87);
    });

    test('contact fields excluded when includeContactFields is false', () {
      final req = _request().copyWith(
        contactPhone: '+250788111111',
        contactName: 'Test',
      );
      final json = req.toJson(includeContactFields: false);

      expect(json.containsKey('contact_phone'), isFalse);
      expect(json.containsKey('contact_name'), isFalse);
    });

    test('driver return sets trip_type and role correctly', () {
      final req = _request(isDriverReturnTrip: true);
      final json = req.toJson();

      expect(json['trip_type'], 'driver_return');
      expect(json['role'], 'DRIVER');
    });

    test('recurring days are serialized', () {
      final req = _request().copyWith(
        recurringDays: [TripWeekday.mon, TripWeekday.fri],
      );
      final json = req.toJson();

      expect(json['repeat_days'], ['mon', 'fri']);
      expect(json['is_recurring_trip'], isTrue);
    });
  });

  group('TripPostRequest.toJson expires_at', () {
    test('expires_at is 1 hour after departure', () {
      final req = _request();
      final json = req.toJson();

      final departure = DateTime.parse(json['travel_time'] as String);
      final expires = DateTime.parse(json['expires_at'] as String);

      expect(expires.difference(departure), const Duration(hours: 1));
    });

    test('includes all canonical column names', () {
      final req = _request(clientRequestId: 'req-json');
      final json = req.toJson();

      expect(json.containsKey('travel_time'), isTrue);
      expect(json.containsKey('vehicle_type'), isTrue);
      expect(json.containsKey('seats'), isTrue);
      expect(json.containsKey('expires_at'), isTrue);
    });
  });

  group('TripVehiclePreference parsing', () {
    test('parses trike and truck correctly', () {
      final trikeReq = _request().copyWith(
        vehiclePreference: TripVehiclePreference.trike,
      );
      final json = trikeReq.toJson();
      expect(json['vehicle_type'], 'trike');

      final truckReq = _request().copyWith(
        vehiclePreference: TripVehiclePreference.truck,
      );
      final json2 = truckReq.toJson();
      expect(json2['vehicle_type'], 'truck');
    });

    test('parses others correctly', () {
      final req = _request().copyWith(
        vehiclePreference: TripVehiclePreference.others,
      );
      final json = req.toJson();
      expect(json['vehicle_type'], 'others');
    });
  });

  group('TripPostRequest.fromOfflineCache', () {
    test('handles canonical format', () {
      final data = <String, dynamic>{
        'from_location': 'A',
        'to_location': 'B',
        'travel_time': _futureDate.toIso8601String(),
        'vehicle_type': 'moto',
        'seats': 2,
        'user_id': 'u1',
        'client_request_id': 'cr1',
        'trip_type': 'driver_return',
      };

      final req = TripPostRequest.fromOfflineCache(data);

      expect(req.fromLocation, 'A');
      expect(req.toLocation, 'B');
      expect(req.vehiclePreference, TripVehiclePreference.moto);
      expect(req.seatsNeeded, 2);
      expect(req.isDriverReturnTrip, isTrue);
      expect(req.clientRequestId, 'cr1');
    });

    test('handles legacy format', () {
      final data = <String, dynamic>{
        'from_location': 'C',
        'to_location': 'D',
        'departure_at': _futureDate.toIso8601String(),
        'vehicle_preference': 'cab',
        'seats_needed': 3,
        'user_id': 'u2',
      };

      final req = TripPostRequest.fromOfflineCache(data);

      expect(req.fromLocation, 'C');
      expect(req.vehiclePreference, TripVehiclePreference.cab);
      expect(req.seatsNeeded, 3);
      expect(req.isDriverReturnTrip, isFalse);
    });

    test('handles mixed canonical + legacy coordinate keys', () {
      final data = <String, dynamic>{
        'from_location': 'E',
        'to_location': 'F',
        'travel_time': _futureDate.toIso8601String(),
        'from_lat': -1.95,
        'from_lng': 30.06,
        'latitude': -2.0, // legacy key, should be ignored when from_lat exists
        'longitude': 31.0,
      };

      final req = TripPostRequest.fromOfflineCache(data);

      expect(req.latitude, -1.95); // canonical 'from_lat' takes priority
      expect(req.longitude, 30.06);
    });

    test('throws FormatException on missing departure', () {
      expect(
        () => TripPostRequest.fromOfflineCache(<String, dynamic>{
          'from_location': 'E',
          'to_location': 'F',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('defaults seats to 1 when missing', () {
      final data = <String, dynamic>{
        'from_location': 'G',
        'to_location': 'H',
        'travel_time': _futureDate.toIso8601String(),
      };

      final req = TripPostRequest.fromOfflineCache(data);

      expect(req.seatsNeeded, 1);
    });

    test('defaults vehicle preference to any', () {
      final data = <String, dynamic>{
        'from_location': 'I',
        'to_location': 'J',
        'travel_time': _futureDate.toIso8601String(),
      };

      final req = TripPostRequest.fromOfflineCache(data);

      expect(req.vehiclePreference, TripVehiclePreference.any);
    });
  });

  group('TripPostRequest.copyWith', () {
    test('preserves unmodified fields', () {
      final original = _request(clientRequestId: 'original');
      final modified = original.copyWith(toLocation: 'New Place');

      expect(modified.fromLocation, 'Kigali Heights');
      expect(modified.toLocation, 'New Place');
      expect(modified.clientRequestId, 'original');
      expect(modified.seatsNeeded, 1);
    });

    test('can set nullable fields to null', () {
      final original = _request(clientRequestId: 'has-id');
      final modified = original.copyWith(clientRequestId: null);

      expect(modified.clientRequestId, isNull);
    });

    test('preserves nested lists', () {
      final original = _request().copyWith(
        recurringDays: [TripWeekday.mon],
      );
      final modified = original.copyWith(toLocation: 'Somewhere');

      expect(modified.recurringDays, [TripWeekday.mon]);
    });
  });

  group('TripPostRequest boolean getters', () {
    test('isReturnTrip true when returnAt is set', () {
      final req = _request().copyWith(
        returnAt: _futureDate.add(const Duration(hours: 4)),
      );

      expect(req.isReturnTrip, isTrue);
    });

    test('isReturnTrip false when returnAt is null', () {
      expect(_request().isReturnTrip, isFalse);
    });

    test('isRecurringTrip true when recurringDays non-empty', () {
      final req = _request().copyWith(
        recurringDays: [TripWeekday.wed],
      );

      expect(req.isRecurringTrip, isTrue);
    });

    test('isRecurringTrip false for empty list', () {
      expect(_request().isRecurringTrip, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // TripSyncSummary
  // ═════════════════════════════════════════════════════════════════════════════

  group('TripSyncSummary', () {
    test('stores all counts correctly', () {
      const summary = TripSyncSummary(
        pendingCount: 5,
        syncedCount: 3,
        failedCount: 1,
        discardedCount: 1,
      );

      expect(summary.pendingCount, 5);
      expect(summary.syncedCount, 3);
      expect(summary.failedCount, 1);
      expect(summary.discardedCount, 1);
    });
  });
}
