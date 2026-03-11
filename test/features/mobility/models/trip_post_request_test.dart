import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/mobility/models/trip_post_request.dart';

void main() {
  test('toJson includes resolved pickup and destination coordinates', () {
    final request = TripPostRequest(
      fromLocation: 'Nyamirambo',
      toLocation: 'Kigali Heights',
      departureAt: DateTime.utc(2026, 3, 12, 7, 30),
      returnAt: DateTime.utc(2026, 3, 12, 18),
      vehiclePreference: TripVehiclePreference.cab,
      seatsNeeded: 2,
      recurringDays: const <TripWeekday>[TripWeekday.mon, TripWeekday.wed],
      latitude: -1.959,
      longitude: 30.044,
      destinationLatitude: -1.949,
      destinationLongitude: 30.092,
      contactPhone: '250788000111',
      contactName: 'Test Rider',
    );

    final payload = request.toJson();

    expect(payload['travel_time'], '2026-03-12T07:30:00.000Z');
    expect(payload['return_at'], '2026-03-12T18:00:00.000Z');
    expect(payload['vehicle_type'], 'cab');
    expect(payload['seats'], 2);
    expect(payload['trip_type'], 'passenger');
    expect(payload['is_return_trip'], isTrue);
    expect(payload['is_recurring_trip'], isTrue);
    expect(payload['repeat_days'], <String>['mon', 'wed']);
    expect(payload['from_lat'], -1.959);
    expect(payload['from_lng'], 30.044);
    expect(payload['to_lat'], -1.949);
    expect(payload['to_lng'], 30.092);
    expect(payload['contact_phone'], '250788000111');
    expect(payload['contact_name'], 'Test Rider');
    expect(payload['whatsapp_number'], '250788000111');
    expect(payload['status'], 'open');
  });

  test('toJson normalizes driver return payloads for the live schema', () {
    final request = TripPostRequest(
      fromLocation: 'Remera',
      toLocation: 'Kimironko',
      departureAt: DateTime.utc(2026, 3, 13, 8),
      vehiclePreference: TripVehiclePreference.moto,
      seatsNeeded: 1,
      latitude: -1.9441,
      longitude: 30.0619,
      isDriverReturnTrip: true,
    );

    final payload = request.toJson();

    expect(payload['travel_time'], '2026-03-13T08:00:00.000Z');
    expect(payload['vehicle_type'], 'moto');
    expect(payload['role'], 'DRIVER');
    expect(payload['trip_type'], 'driver_return');
    expect(payload['is_driver_return_trip'], isTrue);
    expect(payload['from_lat'], -1.9441);
    expect(payload['from_lng'], 30.0619);
    expect(payload['status'], 'open');
  });
}
