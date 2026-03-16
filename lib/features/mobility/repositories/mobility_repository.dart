import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/identity/user_identity_lookup.dart';
import 'package:cool_app/core/utils/json_helpers.dart' as jh;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/identity/public_user_identity.dart';
import '../models/driver_info.dart';
import '../models/driver_profile.dart';
import '../models/trip.dart';
import '../models/trip_type.dart';

class MobilityRepository {
  MobilityRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;
  static const _regularDriverTripThreshold = 15;
  static const _tripSelect =
      'id, user_id, role, vehicle_type, trip_type, from_location, from_lat, '
      'from_lng, to_location, to_lat, to_lng, travel_time, repeat_days, '
      'status, contact_phone, contact_name, whatsapp_number, created_at';

  Future<List<DriverInfo>> getNearbyDrivers(
    double lat,
    double lng,
    String? vehicleType,
    String? country,
  ) async {
    final normalizedVehicleType = _normalizedVehicleType(vehicleType);
    final response = await _client.rpc(
      'get_nearby_drivers',
      params: <String, dynamic>{
        'p_lat': lat,
        'p_lng': lng,
        'p_vehicle_type': normalizedVehicleType,
        'p_country': country,
        'radius_km': 10,
      },
    );

    final driverRows = jh.asListOfMaps(response);

    if (driverRows.isEmpty) {
      return const <DriverInfo>[];
    }

    final userIds = driverRows
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final profilesById = await _loadProfilesById(userIds);
    final driverMetaByUser = await _loadDriverMetaByUser(userIds);

    final drivers =
        driverRows
            .map((row) {
              final userId = row['user_id']?.toString() ?? '';
              final profile = profilesById[userId] ?? const <String, dynamic>{};
              final driverMeta =
                  driverMetaByUser[userId] ?? const <String, dynamic>{};
              final vehicleTypeValue = row['vehicle_type']?.toString() ?? '';
              final displayName = PublicUserIdentity.resolve(
                publicUserId: profile['public_user_id']?.toString(),
                userId: userId,
                phone: profile['phone']?.toString(),
              );
              final driverLat = jh.asDouble(row['latitude']);
              final driverLng = jh.asDouble(row['longitude']);
              final distanceKm = jh.asDouble(row['distance_km']) ?? 0;
              final tripCount = jh.asInt(row['trip_count']) ?? 0;
              final driverTripsDone = jh.asInt(driverMeta['trips_done']) ?? 0;

              return DriverInfo(
                driverId: userId,
                displayName: displayName,
                vehicleType: _vehicleLabel(vehicleTypeValue),
                vehicleEmoji: _vehicleEmoji(vehicleTypeValue),
                distanceKm: distanceKm,
                isOnline: jh.asBool(row['is_online']),
                tripCount: tripCount,
                scheduledRoute: row['scheduled_route']?.toString(),
                hasReturnTrip: jh.asBool(row['has_return_trip']),
                contactPhone: profile['phone']?.toString(),
                baseLocation: driverMeta['base_location']?.toString(),
                vehicleStatus: driverMeta['vehicle_status']?.toString(),
                isRegularDriver:
                    tripCount >= _regularDriverTripThreshold ||
                    driverTripsDone >= _regularDriverTripThreshold,
                lastActiveAt: jh.parseDateTime(driverMeta['updated_at']),
                latitude: driverLat,
                longitude: driverLng,
              );
            })
            .toList(growable: false)
          ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    if (drivers.length <= 30) {
      return drivers;
    }
    return drivers.take(30).toList(growable: false);
  }

  Future<List<Trip>> getScheduledTrips(
    double lat,
    double lng,
    String? vehicleType,
    TripType type,
    String? country,
  ) async {
    final normalizedVehicleType = _normalizedVehicleType(vehicleType);
    final tripType = type.isDriverReturn ? 'driver_return' : 'passenger';

    final response = await _client.rpc(
      'get_scheduled_trips',
      params: <String, dynamic>{
        'p_lat': lat,
        'p_lng': lng,
        'p_vehicle_type': normalizedVehicleType,
        'p_trip_type': tripType,
        'p_country': country,
        'radius_km': 10,
      },
    );

    final rows = jh.asListOfMaps(response);
    return _hydrateTrips(rows, originLat: lat, originLng: lng);
  }

  Future<Trip> createTrip(Trip trip) async {
    final inserted = await _client
        .from('mobility_trips')
        .insert(trip.toInsertJson())
        .select(_tripSelect)
        .single();

    return Trip.fromJson(jh.asMap(inserted));
  }

  Future<List<Trip>> getMyTrips(String userId) async {
    final query = _client
        .from('mobility_trips')
        .select(_tripSelect)
        .eq('user_id', userId);

    final response = await query
        .order('travel_time', ascending: true)
        .order('created_at', ascending: false);

    final rows = jh
        .asListOfMaps(response)
        .where((row) => _isVisibleTripStatus(row['status']))
        .toList(growable: false);
    return _hydrateTrips(rows);
  }

  Future<void> setDriverOnline(
    String userId,
    bool isOnline,
    double lat,
    double lng, {
    String? vehicleType,
    String? vehicleDescription,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'is_online': isOnline,
      'latitude': lat,
      'longitude': lng,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if ((vehicleType ?? '').trim().isNotEmpty) {
      payload['vehicle_type'] = vehicleType!.trim();
    }
    if ((vehicleDescription ?? '').trim().isNotEmpty) {
      payload['plate_number'] = vehicleDescription!.trim();
    }

    await _client
        .from('driver_profiles')
        .upsert(payload, onConflict: 'user_id');
  }

  Future<void> cancelTrip(String tripId) async {
    await _client
        .from('mobility_trips')
        .update(<String, dynamic>{'status': 'cancelled'})
        .eq('id', tripId);
  }

  Future<void> pauseTrip(String tripId) async {
    await _client
        .from('mobility_trips')
        .update(<String, dynamic>{'status': 'paused'})
        .eq('id', tripId);
  }

  Future<void> repostTrip(String tripId) async {
    await _client
        .from('mobility_trips')
        .update(<String, dynamic>{'status': 'active'})
        .eq('id', tripId);
  }

  Future<void> deleteTrip(String tripId) async {
    await _client.from('mobility_trips').delete().eq('id', tripId);
  }

  Future<DriverProfile?> getDriverProfile(String userId) async {
    final query = _client
        .from('driver_profiles')
        .select()
        .eq('user_id', userId);

    final row = await query.maybeSingle();

    if (row == null) {
      return null;
    }

    final profileFuture = _loadProfileById(userId);
    final tripCountFuture = _loadTripCount(userId);
    final profile = await profileFuture;
    final tripCount = await tripCountFuture;
    return DriverProfile.fromJson(<String, dynamic>{
      ...jh.asMap(row),
      'profile': profile,
      'trip_count': tripCount,
    });
  }

  Future<DriverProfile> updateVehicle(
    String userId,
    String type,
    String plateNumber,
    String baseLocation,
  ) async {
    await _client.from('driver_profiles').upsert(<String, dynamic>{
      'user_id': userId,
      'vehicle_type': type.trim(),
      'plate_number': plateNumber.trim(),
      'base_location': baseLocation.trim(),
      'vehicle_status': 'pending_review',
    }, onConflict: 'user_id');

    final profile = await getDriverProfile(userId);
    if (profile == null) {
      throw StateError('Driver profile could not be loaded after update.');
    }
    return profile;
  }

  Future<List<Trip>> _hydrateTrips(
    List<Map<String, dynamic>> rows, {
    double? originLat,
    double? originLng,
  }) async {
    if (rows.isEmpty) {
      return const <Trip>[];
    }

    final userIds = rows
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final profilesById = await _loadProfilesById(userIds);

    final trips =
        rows
            .map((row) {
              final tripLat = jh.asDouble(row['from_lat']);
              final tripLng = jh.asDouble(row['from_lng']);
              final distanceKm =
                  originLat == null ||
                      originLng == null ||
                      tripLat == null ||
                      tripLng == null
                  ? null
                  : GeoPoint(
                      latitude: originLat,
                      longitude: originLng,
                    ).distanceToKm(
                      GeoPoint(latitude: tripLat, longitude: tripLng),
                    );

              return Trip.fromJson(<String, dynamic>{
                ...row,
                'distance_km': distanceKm,
                'profile': profilesById[row['user_id']?.toString()] ?? const {},
              });
            })
            .toList(growable: false)
          ..sort((a, b) => a.departureTime.compareTo(b.departureTime));

    return trips;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfilesById(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }

    try {
      final rows = await fetchUserIdentityRows(
        fetchRows: ({required includePublicUserId}) async => jh.asListOfMaps(
          await _client
              .from('users')
              .select(
                buildUserIdentitySelect(
                  includePublicUserId: includePublicUserId,
                  extraColumns: const <String>['avatar_url'],
                ),
              )
              .inFilter('id', userIds),
        ),
      );
      return {
        for (final row in rows)
          if ((row['id']?.toString() ?? '').isNotEmpty)
            row['id'].toString(): row,
      };
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  Future<Map<String, dynamic>> _loadProfileById(String userId) async {
    final profiles = await _loadProfilesById(<String>[userId]);
    return profiles[userId] ?? const <String, dynamic>{};
  }

  Future<Map<String, Map<String, dynamic>>> _loadDriverMetaByUser(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const <String, Map<String, dynamic>>{};
    }

    try {
      final response = await _client
          .from('driver_profiles')
          .select(
            'user_id, vehicle_status, base_location, trips_done, updated_at',
          )
          .inFilter('user_id', userIds);
      final rows = jh.asListOfMaps(response);
      return {
        for (final row in rows)
          if ((row['user_id']?.toString() ?? '').isNotEmpty)
            row['user_id'].toString(): row,
      };
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  Future<int> _loadTripCount(String userId) async {
    final response = await _client
        .from('mobility_trips')
        .select('id, status')
        .eq('user_id', userId);
    return jh
        .asListOfMaps(response)
        .where((row) => _isVisibleTripStatus(row['status']))
        .length;
  }
}

String? _normalizedVehicleType(String? vehicleType) {
  if (vehicleType == null) {
    return null;
  }

  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'all') {
    return null;
  }
  if (normalized.contains('moto')) {
    return 'moto';
  }
  if (normalized.contains('cab')) {
    return 'cab';
  }
  if (normalized.contains('truck')) {
    return 'truck';
  }
  if (normalized.contains('trike') || normalized.contains('van')) {
    return 'trike';
  }
  return normalized;
}

String _vehicleLabel(String rawValue) {
  switch (_normalizedVehicleType(rawValue)) {
    case 'moto':
      return 'Moto';
    case 'cab':
      return 'Cab';
    case 'truck':
      return 'Truck';
    case 'trike':
      return 'Trike';
    default:
      return rawValue.trim().isEmpty ? 'Vehicle' : rawValue.trim();
  }
}

String _vehicleEmoji(String rawValue) {
  switch (_normalizedVehicleType(rawValue)) {
    case 'moto':
      return '🛺';
    case 'cab':
      return '🚗';
    case 'truck':
      return '🚛';
    case 'trike':
      return '🚐';
    default:
      return '🚘';
  }
}

/// Whether a trip status should be visible in the user's own trip list.
/// Includes paused trips so users can repost them.
bool _isVisibleTripStatus(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'active' ||
      normalized == 'open' ||
      normalized == 'paused';
}
