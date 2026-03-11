import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/models/trip_type.dart';

void main() {
  group('Trip serialization', () {
    test('toInsertJson trip_type matches TripType enum values', () {
      final passengerTrip = Trip(
        userId: 'u1',
        fromLocation: 'A',
        toLocation: 'B',
        departureTime: DateTime(2026, 3, 15, 8, 0),
        vehicleType: 'moto',
      );

      final insertJson = passengerTrip.toInsertJson();
      expect(insertJson['trip_type'], TripType.passenger.name);

      // Verify fromJson can read back what toInsertJson writes
      final roundTripped = Trip.fromJson({
        ...insertJson,
        'id': 'test-id',
        'travel_time': insertJson['travel_time'],
      });
      expect(roundTripped.tripType, TripType.passenger);
    });

    test('toInsertJson trip_type for driver return trip', () {
      final driverTrip = Trip(
        userId: 'u1',
        fromLocation: 'A',
        toLocation: 'B',
        departureTime: DateTime(2026, 3, 15, 8, 0),
        vehicleType: 'cab',
        isDriverReturnTrip: true,
        role: 'DRIVER',
      );

      final insertJson = driverTrip.toInsertJson();
      expect(insertJson['trip_type'], TripType.driverReturn.name);

      final roundTripped = Trip.fromJson({
        ...insertJson,
        'id': 'test-id',
        'travel_time': insertJson['travel_time'],
      });
      expect(roundTripped.tripType, TripType.driverReturn);
    });

    test('toJson and toInsertJson produce same trip_type format', () {
      final trip = Trip(
        userId: 'u1',
        fromLocation: 'X',
        toLocation: 'Y',
        departureTime: DateTime(2026, 3, 15),
        vehicleType: 'moto',
      );

      expect(trip.toJson()['trip_type'], trip.toInsertJson()['trip_type']);
    });
  });
}
