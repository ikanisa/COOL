import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/models/trip_type.dart';
import 'package:cool_app/features/mobility/providers/trip_board_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';

void main() {
  group('TripBoardNotifier', () {
    test(
      'refresh loads public trips and my trips while excluding own public posts',
      () async {
        final repository = FakeMobilityRepository(
          scheduledTrips: <Trip>[
            trip(id: 'mine-open', userId: 'user-1', from: 'Kigali', to: 'Huye'),
            trip(
              id: 'other-open',
              userId: 'user-2',
              from: 'Remera',
              to: 'Musanze',
              contactPhone: '250788000111',
            ),
          ],
        );
        final notifier = TripBoardNotifier(
          repository: repository,
          authState: AuthState(user: testUser()),
        );

        notifier.updateLocation(
          const GeoPoint(latitude: -1.9441, longitude: 30.0619),
        );
        await notifier.refresh();

        expect(notifier.state.myTrips.map((trip) => trip.id), ['mine-open']);
        expect(notifier.state.publicTrips.map((trip) => trip.id), [
          'other-open',
        ]);
      },
    );

    test(
      'loadPublicTrips clears nearby trips when there is no location',
      () async {
        final notifier = TripBoardNotifier(
          repository: FakeMobilityRepository(
            scheduledTrips: <Trip>[
              trip(id: 'other-open', userId: 'user-2', from: 'A', to: 'B'),
            ],
          ),
          authState: AuthState(user: testUser()),
        );

        await notifier.loadPublicTrips();

        expect(notifier.state.publicTrips, isEmpty);
        expect(notifier.state.error, isNull);
      },
    );

    test('cancelTrip refreshes my trips with cancelled status', () async {
      final repository = FakeMobilityRepository(
        scheduledTrips: <Trip>[
          trip(id: 'mine-open', userId: 'user-1', from: 'A', to: 'B'),
        ],
      );
      final notifier = TripBoardNotifier(
        repository: repository,
        authState: AuthState(user: testUser()),
      );

      notifier.updateLocation(
        const GeoPoint(latitude: -1.9441, longitude: 30.0619),
      );
      await notifier.refresh();
      final succeeded = await notifier.cancelTrip('mine-open');

      expect(succeeded, isTrue);
      expect(notifier.state.myTrips.single.status, 'cancelled');
    });

    test('deleteTrip removes the trip from state', () async {
      final repository = FakeMobilityRepository(
        scheduledTrips: <Trip>[
          trip(id: 'mine-open', userId: 'user-1', from: 'A', to: 'B'),
        ],
      );
      final notifier = TripBoardNotifier(
        repository: repository,
        authState: AuthState(user: testUser()),
      );

      notifier.updateLocation(
        const GeoPoint(latitude: -1.9441, longitude: 30.0619),
      );
      await notifier.refresh();
      final succeeded = await notifier.deleteTrip('mine-open');

      expect(succeeded, isTrue);
      expect(notifier.state.myTrips, isEmpty);
    });
  });
}

class FakeMobilityRepository extends MobilityRepository {
  FakeMobilityRepository({required List<Trip> scheduledTrips})
    : _scheduledTrips = List<Trip>.from(scheduledTrips),
      super(client: SupabaseClient('http://localhost', 'public-anon-key'));

  final List<Trip> _scheduledTrips;

  @override
  Future<List<Trip>> getScheduledTrips(
    double lat,
    double lng,
    String? vehicleType,
    TripType type,
    String? country,
  ) async {
    return _scheduledTrips
        .where((trip) => trip.tripType == type)
        .where(
          (trip) =>
              vehicleType == null ||
              trip.vehicleType.toLowerCase() == vehicleType,
        )
        .toList(growable: false);
  }

  @override
  Future<List<Trip>> getMyTrips(String userId, {String? country}) async {
    return _scheduledTrips
        .where((trip) => trip.userId == userId)
        .toList(growable: false);
  }

  @override
  Future<void> cancelTrip(String tripId) async {
    final index = _scheduledTrips.indexWhere((trip) => trip.id == tripId);
    if (index == -1) {
      return;
    }

    final existing = _scheduledTrips[index];
    _scheduledTrips[index] = Trip(
      id: existing.id,
      userId: existing.userId,
      fromLocation: existing.fromLocation,
      toLocation: existing.toLocation,
      departureTime: existing.departureTime,
      vehicleType: existing.vehicleType,
      vehicleEmoji: existing.vehicleEmoji,
      seats: existing.seats,
      isReturn: existing.isReturn,
      isRecurring: existing.isRecurring,
      isDriverReturnTrip: existing.isDriverReturnTrip,
      returnTime: existing.returnTime,
      expiresAt: existing.expiresAt,
      latitude: existing.latitude,
      longitude: existing.longitude,
      distanceKm: existing.distanceKm,
      status: 'cancelled',
      contactPhone: existing.contactPhone,
      contactName: existing.contactName,
    );
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    _scheduledTrips.removeWhere((trip) => trip.id == tripId);
  }
}

Trip trip({
  required String id,
  required String userId,
  required String from,
  required String to,
  String vehicleType = 'moto',
  String status = 'open',
  bool isDriverReturnTrip = false,
  String? contactPhone,
}) {
  return Trip(
    id: id,
    userId: userId,
    fromLocation: from,
    toLocation: to,
    departureTime: DateTime.now().add(const Duration(hours: 2)),
    vehicleType: vehicleType,
    seats: 1,
    status: status,
    isDriverReturnTrip: isDriverReturnTrip,
    contactPhone: contactPhone,
  );
}

UserProfile testUser() {
  return const UserProfile(
    id: 'user-1',
    phone: '250788000001',
    fullName: 'Test Rider',
    momoNumber: '250788000001',
    momoProvider: 'mtn',
    country: 'RW',
    languageCode: 'en',
    isDriver: false,
  );
}
