import 'dart:math' as math;

import 'package:cool_app/core/config/env_config.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/performance_dio_interceptor.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final placeSearchServiceProvider = Provider<PlaceSearchService>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.mobilityGeocodingBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: <String, dynamic>{
        'Accept': 'application/json',
        'User-Agent': EnvConfig.mobilityGeocodingUserAgent,
      },
    ),
  );

  dio.interceptors.add(PerformanceDioInterceptor());

  return MapsGatewayPlaceSearchService(
    client: Supabase.instance.client,
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
        body: <String, dynamic>{
          'action': 'autocomplete',
          'query': normalized,
          'languageCode': languageTag,
          'sessionToken': sessionToken,
          'limit': limit.clamp(1, 8),
          if (near != null)
            'near': <String, dynamic>{
              'latitude': near.latitude,
              'longitude': near.longitude,
            },
        },
      );

      final data = _asMap(response.data);
      if (data['success'] == false) {
        throw StateError(data['message']?.toString() ?? 'Autocomplete failed.');
      }

      final suggestions = _asList(data['suggestions']);
      final results = suggestions
          .whereType<Map>()
          .map(
            (row) => PlaceSearchResult.fromMapsGatewayJson(
              Map<String, dynamic>.from(row),
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
        languageTag: languageTag,
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
        body: <String, dynamic>{
          'action': 'place_details',
          'placeId': placeId,
          'languageCode': languageTag,
          'sessionToken': sessionToken,
        },
      );

      final data = _asMap(response.data);
      if (data['success'] == false) {
        throw StateError(
          data['message']?.toString() ?? 'Place resolution failed.',
        );
      }

      final place = PlaceSearchResult.fromMapsGatewayJson(
        _asMap(data['place']),
      );
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
        languageTag: languageTag,
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
        body: <String, dynamic>{
          'action': 'reverse_geocode',
          'location': <String, dynamic>{
            'latitude': latitude,
            'longitude': longitude,
          },
          'languageCode': languageTag,
        },
      );

      final data = _asMap(response.data);
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
      return PlaceSearchResult.fromMapsGatewayJson(_asMap(place));
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
        languageTag: languageTag,
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
        body: <String, dynamic>{
          'action': 'compute_route',
          'origin': <String, dynamic>{
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
          'destination': <String, dynamic>{
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
          'languageCode': languageTag,
          'travelMode': travelMode.apiValue,
        },
      );

      final data = _asMap(response.data);
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
        _asMap(route),
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
        languageTag: languageTag,
        travelMode: travelMode,
      );
    }
  }
}

class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

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

    final viewBox = near == null ? null : _buildViewBox(near);
    final queryParameters = <String, dynamic>{
      'q': normalized,
      'format': 'jsonv2',
      'addressdetails': 1,
      'limit': limit.clamp(1, 8),
      'dedupe': 1,
    };
    if (languageTag?.isNotEmpty ?? false) {
      queryParameters['accept-language'] = languageTag;
    }
    if (viewBox != null) {
      queryParameters['viewbox'] = viewBox;
    }

    final headers = <String, dynamic>{};
    if (languageTag?.isNotEmpty ?? false) {
      headers['Accept-Language'] = languageTag;
    }

    final response = await _dio.get<List<dynamic>>(
      '/search',
      queryParameters: queryParameters,
      options: Options(headers: headers),
    );

    final rows = response.data ?? const <dynamic>[];
    return rows
        .whereType<Map>()
        .map(
          (row) => PlaceSearchResult.fromNominatimJson(
            Map<String, dynamic>.from(row),
          ),
        )
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
    final response = await _dio.get<Map<String, dynamic>>(
      '/reverse',
      queryParameters: <String, dynamic>{
        'lat': latitude,
        'lon': longitude,
        'format': 'jsonv2',
        'addressdetails': 1,
        'zoom': 18,
        if (languageTag != null && languageTag.isNotEmpty)
          'accept-language': languageTag,
      },
      options: Options(
        headers: <String, dynamic>{
          if (languageTag != null && languageTag.isNotEmpty)
            'Accept-Language': languageTag,
        },
      ),
    );

    final data = response.data;
    if (data == null || data.isEmpty) {
      return null;
    }

    return PlaceSearchResult.fromNominatimJson(data);
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

  String _buildViewBox(GeoPoint near) {
    const spanKm = 12.0;
    final latDelta = spanKm / 111.0;
    final safeCos = math.max(math.cos(near.latitude * math.pi / 180), 0.2);
    final lngDelta = spanKm / (111.0 * safeCos);
    final west = near.longitude - lngDelta;
    final east = near.longitude + lngDelta;
    final north = near.latitude + latDelta;
    final south = near.latitude - latDelta;
    return '$west,$north,$east,$south';
  }
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

  factory PlaceSearchResult.fromNominatimJson(Map<String, dynamic> json) {
    final displayName = json['display_name']?.toString().trim() ?? '';
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final primary = _resolvePrimaryText(json, parts);
    final secondary = _resolveSecondaryText(parts, primary);
    final latitude = _parseDouble(json['lat']);
    final longitude = _parseDouble(json['lon']);

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

  factory PlaceSearchResult.fromMapsGatewayJson(Map<String, dynamic> json) {
    final primary = json['primaryText']?.toString().trim();
    final secondary = json['secondaryText']?.toString().trim();
    final label = json['label']?.toString().trim();
    final location = _asMap(json['position']);
    final latitude = _parseDouble(location['latitude']);
    final longitude = _parseDouble(location['longitude']);

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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  if (value is List<dynamic>) {
    return value;
  }
  if (value is List) {
    return List<dynamic>.from(value);
  }
  return const <dynamic>[];
}

String _resolvePrimaryText(Map<String, dynamic> json, List<String> parts) {
  final address = _asMap(json['address']);
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
    parts.isEmpty ? null : parts.first,
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

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
