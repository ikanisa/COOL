import 'package:cool_app/core/utils/json_helpers.dart' as jh;
import 'package:cool_app/core/config/env_config.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supabase_client_provider.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/performance_dio_interceptor.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Geo bounds for the active market. Hardcoded for RW now; when AppMarket
/// expands, derive from a market config table.
const _marketBounds = _GeoBounds(
  south: -2.95,
  west: 28.8,
  north: -1.0,
  east: 30.95,
);
const _marketLanguageTag = 'en';
const _marketCountryCode = 'rw';

final placeSearchServiceProvider = Provider<PlaceSearchService>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.mobilityGeocodingBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: <String, Object?>{
        'Accept': 'application/json',
        'User-Agent': EnvConfig.mobilityGeocodingUserAgent,
      },
    ),
  );

  dio.interceptors.add(PerformanceDioInterceptor());

  return MapsGatewayPlaceSearchService(
    client: ref.read(supabaseClientProvider),
    fallback: NominatimPlaceSearchService(dio: dio),
    performance: ref.read(performanceServiceProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
  );
});

abstract class PlaceSearchService {
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    GeoPoint? near,
    String? languageTag,
    String? sessionToken,
    int limit = 5,
  });

  Future<PlaceSearchResult?> geocodeQuery(
    String query, {
    GeoPoint? near,
    String? languageTag,
    int limit = 1,
  });

  Future<PlaceSearchResult> resolvePlace(
    PlaceSearchResult prediction, {
    String? languageTag,
    String? sessionToken,
  });

  Future<PlaceSearchResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String? languageTag,
  });

  Future<MobilityRoutePreview?> computeRoutePreview({
    required GeoPoint origin,
    required GeoPoint destination,
    String? languageTag,
    MobilityRouteTravelMode travelMode = MobilityRouteTravelMode.drive,
  });
}

class MapsGatewayPlaceSearchService implements PlaceSearchService {
  MapsGatewayPlaceSearchService({
    required SupabaseClient client,
    required PlaceSearchService fallback,
    required PerformanceService performance,
    required CrashlyticsService crashlytics,
  }) : _client = client,
       _fallback = fallback,
       _performance = performance,
       _crashlytics = crashlytics;

  final SupabaseClient _client;
  final PlaceSearchService _fallback;
  final PerformanceService _performance;
  final CrashlyticsService _crashlytics;

  @override
  Future<PlaceSearchResult?> geocodeQuery(
    String query, {
    GeoPoint? near,
    String? languageTag,
    int limit = 1,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) {
      return null;
    }

    _performance.startTrace('maps_place_geocode');

    try {
      final response = await _client.functions.invoke(
        'maps-gateway',
        body: <String, Object?>{
          'action': 'text_search',
          'query': normalized,
          'languageCode': _normalizedLanguageTag(languageTag),
          'limit': limit.clamp(1, 5),
          if (near != null)
            'near': <String, Object?>{
              'latitude': near.latitude,
              'longitude': near.longitude,
            },
        },
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == false) {
        throw StateError(data['message']?.toString() ?? 'Geocoding failed.');
      }

      final results = _asList(data['places'])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (row) => PlaceSearchResult.fromMapsGatewayJson(
              Map<String, Object?>.from(row),
            ),
          )
          .where(_isMarketResult)
          .where((place) => place.label.isNotEmpty)
          .toList(growable: false);
      final result = results.isEmpty ? null : results.first;

      _performance.stopTrace(
        'maps_place_geocode',
        metrics: <String, int>{'count': result == null ? 0 : 1},
      );
      return result;
    } catch (error, stackTrace) {
      _performance.stopTrace(
        'maps_place_geocode',
        attributes: <String, String>{
          'error': error.runtimeType.toString(),
          'fallback': 'nominatim',
        },
      );
      _crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'maps_place_geocode',
      );
      return _fallback.geocodeQuery(
        normalized,
        near: near,
        languageTag: _normalizedLanguageTag(languageTag),
        limit: limit,
      );
    }
  }

  @override
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    GeoPoint? near,
    String? languageTag,
    String? sessionToken,
    int limit = 5,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) {
      return const <PlaceSearchResult>[];
    }

    _performance.startTrace('maps_place_autocomplete');

    try {
      final response = await _client.functions.invoke(
        'maps-gateway',
        body: <String, Object?>{
          'action': 'autocomplete',
          'query': normalized,
          'languageCode': _normalizedLanguageTag(languageTag),
          'sessionToken': sessionToken,
          'limit': limit.clamp(1, 8),
          if (near != null)
            'near': <String, Object?>{
              'latitude': near.latitude,
              'longitude': near.longitude,
            },
        },
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == false) {
        throw StateError(data['message']?.toString() ?? 'Autocomplete failed.');
      }

      final suggestions = _asList(data['suggestions']);
      final results = suggestions
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (row) => PlaceSearchResult.fromMapsGatewayJson(
              Map<String, Object?>.from(row),
            ),
          )
          .where((result) => result.label.isNotEmpty)
          .toList(growable: false);

      _performance.stopTrace(
        'maps_place_autocomplete',
        metrics: <String, int>{'count': results.length},
      );
      return results;
    } catch (error, stackTrace) {
      _performance.stopTrace(
        'maps_place_autocomplete',
        attributes: <String, String>{
          'error': error.runtimeType.toString(),
          'fallback': 'nominatim',
        },
      );
      _crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'maps_place_autocomplete',
      );
      return _fallback.searchPlaces(
        normalized,
        near: near,
        languageTag: _normalizedLanguageTag(languageTag),
        sessionToken: sessionToken,
        limit: limit,
      );
    }
  }

  @override
  Future<PlaceSearchResult> resolvePlace(
    PlaceSearchResult prediction, {
    String? languageTag,
    String? sessionToken,
  }) async {
    if (prediction.hasCoordinates) {
      return prediction;
    }

    final placeId = prediction.placeId?.trim();
    if (placeId == null || placeId.isEmpty) {
      throw StateError('A Google place prediction is required.');
    }

    _performance.startTrace('maps_place_details');

    try {
      final response = await _client.functions.invoke(
        'maps-gateway',
        body: <String, Object?>{
          'action': 'place_details',
          'placeId': placeId,
          'languageCode': _normalizedLanguageTag(languageTag),
          'sessionToken': sessionToken,
        },
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == false) {
        throw StateError(
          data['message']?.toString() ?? 'Place resolution failed.',
        );
      }

      final place = PlaceSearchResult.fromMapsGatewayJson(
        jh.asMapOrEmpty(data['place']),
      );
      if (!_isMarketResult(place)) {
        throw StateError('Place is outside the Rwanda market.');
      }
      _performance.stopTrace('maps_place_details');
      return place;
    } catch (error, stackTrace) {
      _performance.stopTrace(
        'maps_place_details',
        attributes: <String, String>{'error': error.runtimeType.toString()},
      );
      _crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'maps_place_details',
      );
      return _fallback.resolvePlace(
        prediction,
        languageTag: _normalizedLanguageTag(languageTag),
        sessionToken: sessionToken,
      );
    }
  }

  @override
  Future<PlaceSearchResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String? languageTag,
  }) async {
    _performance.startTrace('maps_reverse_geocode');

    try {
      final response = await _client.functions.invoke(
        'maps-gateway',
        body: <String, Object?>{
          'action': 'reverse_geocode',
          'location': <String, Object?>{
            'latitude': latitude,
            'longitude': longitude,
          },
          'languageCode': _normalizedLanguageTag(languageTag),
        },
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == false) {
        throw StateError(
          data['message']?.toString() ?? 'Reverse geocoding failed.',
        );
      }

      final place = data['place'];
      _performance.stopTrace('maps_reverse_geocode');
      if (place == null) {
        return null;
      }
      final result = PlaceSearchResult.fromMapsGatewayJson(jh.asMapOrEmpty(place));
      return _isMarketResult(result) ? result : null;
    } catch (error, stackTrace) {
      _performance.stopTrace(
        'maps_reverse_geocode',
        attributes: <String, String>{
          'error': error.runtimeType.toString(),
          'fallback': 'nominatim',
        },
      );
      _crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'maps_reverse_geocode',
      );
      return _fallback.reverseGeocode(
        latitude: latitude,
        longitude: longitude,
        languageTag: _normalizedLanguageTag(languageTag),
      );
    }
  }

  @override
  Future<MobilityRoutePreview?> computeRoutePreview({
    required GeoPoint origin,
    required GeoPoint destination,
    String? languageTag,
    MobilityRouteTravelMode travelMode = MobilityRouteTravelMode.drive,
  }) async {
    _performance.startTrace('maps_route_preview');

    try {
      final response = await _client.functions.invoke(
        'maps-gateway',
        body: <String, Object?>{
          'action': 'compute_route',
          'origin': <String, Object?>{
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
          'destination': <String, Object?>{
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
          'languageCode': _normalizedLanguageTag(languageTag),
          'travelMode': travelMode.apiValue,
        },
      );

      final data = jh.asMapOrEmpty(response.data);
      if (data['success'] == false) {
        throw StateError(
          data['message']?.toString() ?? 'Route preview failed.',
        );
      }

      final route = data['route'];
      _performance.stopTrace('maps_route_preview');
      if (route == null) {
        return null;
      }

      return MobilityRoutePreview.fromJson(
        jh.asMapOrEmpty(route),
        origin: origin,
        destination: destination,
      );
    } catch (error, stackTrace) {
      _performance.stopTrace(
        'maps_route_preview',
        attributes: <String, String>{'error': error.runtimeType.toString()},
      );
      _crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'maps_route_preview',
      );
      return _fallback.computeRoutePreview(
        origin: origin,
        destination: destination,
        languageTag: _normalizedLanguageTag(languageTag),
        travelMode: travelMode,
      );
    }
  }
}

class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<PlaceSearchResult?> geocodeQuery(
    String query, {
    GeoPoint? near,
    String? languageTag,
    int limit = 1,
  }) async {
    final results = await searchPlaces(
      query,
      near: near,
      languageTag: languageTag,
      limit: limit,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  @override
  Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    GeoPoint? near,
    String? languageTag,
    String? sessionToken,
    int limit = 5,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) {
      return const <PlaceSearchResult>[];
    }

    final queryParameters = <String, Object?>{
      'q': normalized,
      'format': 'jsonv2',
      'addressdetails': 1,
      'limit': limit.clamp(1, 8),
      'dedupe': 1,
      'countrycodes': _marketCountryCode,
      'viewbox': _marketBounds.nominatimViewBox,
      'bounded': 1,
    };
    final resolvedLanguageTag = _normalizedLanguageTag(languageTag);
    if (resolvedLanguageTag.isNotEmpty) {
      queryParameters['accept-language'] = resolvedLanguageTag;
    }

    final headers = <String, Object?>{};
    if (resolvedLanguageTag.isNotEmpty) {
      headers['Accept-Language'] = resolvedLanguageTag;
    }

    final response = await _dio.get<List<Object?>>(
      '/search',
      queryParameters: queryParameters,
      options: Options(headers: headers),
    );

    final rows = response.data ?? const <Object?>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (row) => PlaceSearchResult.fromNominatimJson(
            Map<String, Object?>.from(row),
          ),
        )
        .where(_isMarketResult)
        .where((result) => result.label.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<PlaceSearchResult> resolvePlace(
    PlaceSearchResult prediction, {
    String? languageTag,
    String? sessionToken,
  }) async {
    if (!prediction.hasCoordinates) {
      throw StateError(
        'Fallback place results do not support deferred lookup.',
      );
    }
    return prediction;
  }

  @override
  Future<PlaceSearchResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String? languageTag,
  }) async {
    if (!_marketBounds.contains(latitude, longitude)) {
      return null;
    }
    final response = await _dio.get<Map<String, Object?>>(
      '/reverse',
      queryParameters: <String, Object?>{
        'lat': latitude,
        'lon': longitude,
        'format': 'jsonv2',
        'addressdetails': 1,
        'zoom': 18,
        if (_normalizedLanguageTag(languageTag).isNotEmpty)
          'accept-language': _normalizedLanguageTag(languageTag),
      },
      options: Options(
        headers: <String, Object?>{
          if (_normalizedLanguageTag(languageTag).isNotEmpty)
            'Accept-Language': _normalizedLanguageTag(languageTag),
        },
      ),
    );

    final data = response.data;
    if (data == null || data.isEmpty) {
      return null;
    }

    final result = PlaceSearchResult.fromNominatimJson(data);
    return _isMarketResult(result) ? result : null;
  }

  @override
  Future<MobilityRoutePreview?> computeRoutePreview({
    required GeoPoint origin,
    required GeoPoint destination,
    String? languageTag,
    MobilityRouteTravelMode travelMode = MobilityRouteTravelMode.drive,
  }) async {
    return null;
  }
}

String _normalizedLanguageTag(String? languageTag) {
  final normalized = languageTag?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return _marketLanguageTag;
  }
  return normalized.startsWith('en') ? _marketLanguageTag : normalized;
}

bool _isMarketResult(PlaceSearchResult result) {
  final position = result.position;
  if (position == null) {
    return true;
  }
  return _marketBounds.contains(position.latitude, position.longitude);
}

class _GeoBounds {
  const _GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double latitude, double longitude) {
    return latitude >= south &&
        latitude <= north &&
        longitude >= west &&
        longitude <= east;
  }

  String get nominatimViewBox => '$west,$north,$east,$south';
}

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.label,
    this.position,
    this.primaryText,
    this.secondaryText,
    this.placeId,
  });

  final String label;
  final GeoPoint? position;
  final String? primaryText;
  final String? secondaryText;
  final String? placeId;

  bool get hasCoordinates => position != null;

  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;

  factory PlaceSearchResult.fromNominatimJson(Map<String, Object?> json) {
    final displayName = json['display_name']?.toString().trim() ?? '';
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final primary = _resolvePrimaryText(json, parts);
    final secondary = _resolveSecondaryText(parts, primary);
    final latitude = jh.asDouble(json['lat']);
    final longitude = jh.asDouble(json['lon']);

    return PlaceSearchResult(
      label: secondary == null || secondary.isEmpty
          ? primary
          : '$primary, $secondary',
      position: latitude == null || longitude == null
          ? null
          : GeoPoint(latitude: latitude, longitude: longitude),
      primaryText: primary,
      secondaryText: secondary,
      placeId: json['place_id']?.toString(),
    );
  }

  factory PlaceSearchResult.fromMapsGatewayJson(Map<String, Object?> json) {
    final primary = json['primaryText']?.toString().trim();
    final secondary = json['secondaryText']?.toString().trim();
    final label = json['label']?.toString().trim();
    final location = jh.asMapOrEmpty(json['position']);
    final latitude = jh.asDouble(location['latitude']);
    final longitude = jh.asDouble(location['longitude']);

    final resolvedPrimary = primary == null || primary.isEmpty
        ? label ?? ''
        : primary;
    final resolvedSecondary = secondary == null || secondary.isEmpty
        ? null
        : secondary;

    return PlaceSearchResult(
      label: (label != null && label.isNotEmpty)
          ? label
          : resolvedSecondary == null
          ? resolvedPrimary
          : '$resolvedPrimary, $resolvedSecondary',
      primaryText: resolvedPrimary.isEmpty ? null : resolvedPrimary,
      secondaryText: resolvedSecondary,
      placeId: json['placeId']?.toString(),
      position: latitude == null || longitude == null
          ? null
          : GeoPoint(latitude: latitude, longitude: longitude),
    );
  }
}

// _asMap consolidated into core/utils/json_helpers.dart (imported as jh).

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

String _resolvePrimaryText(Map<String, Object?> json, List<String> parts) {
  final address = jh.asMapOrEmpty(json['address']);
  final candidates = <String?>[
    json['name']?.toString(),
    address['amenity']?.toString(),
    address['building']?.toString(),
    address['road']?.toString(),
    address['neighbourhood']?.toString(),
    address['suburb']?.toString(),
    address['city']?.toString(),
    address['town']?.toString(),
    address['village']?.toString(),
    address['municipality']?.toString(),
    address['county']?.toString(),
    address['state']?.toString(),
    if (parts.isEmpty) null else parts.first,
  ];

  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String? _resolveSecondaryText(List<String> parts, String primary) {
  if (parts.isEmpty) {
    return null;
  }

  final remaining = parts
      .where((part) => part.toLowerCase() != primary.toLowerCase())
      .toList(growable: false);
  if (remaining.isEmpty) {
    return null;
  }

  return remaining.join(', ');
}

// _parseDouble consolidated into core/utils/json_helpers.dart (imported as jh).
