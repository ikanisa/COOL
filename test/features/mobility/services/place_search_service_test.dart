import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/mobility/services/place_search_service.dart';

void main() {
  group('PlaceSearchResult.fromNominatimJson', () {
    test('derives readable labels from Nominatim payloads', () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'name': 'Kigali Heights',
        'display_name': 'Kigali Heights, KN 5 Road, Nyarugenge, Kigali, Rwanda',
        'lat': '-1.94995',
        'lon': '30.08242',
        'address': <String, dynamic>{
          'road': 'KN 5 Road',
          'city': 'Kigali',
          'country': 'Rwanda',
        },
      });

      expect(
        result.label,
        'Kigali Heights, KN 5 Road, Nyarugenge, Kigali, Rwanda',
      );
      expect(result.primaryText, 'Kigali Heights');
      expect(result.secondaryText, 'KN 5 Road, Nyarugenge, Kigali, Rwanda');
      expect(result.latitude, closeTo(-1.94995, 0.00001));
      expect(result.longitude, closeTo(30.08242, 0.00001));
    });

    test('falls back to address fragments when name is absent', () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'display_name': 'Nyamirambo, Nyarugenge, Kigali, Rwanda',
        'lat': '-1.9753',
        'lon': '30.0394',
        'address': <String, dynamic>{
          'suburb': 'Nyamirambo',
          'city': 'Kigali',
        },
      });

      expect(result.primaryText, 'Nyamirambo');
      expect(result.secondaryText, 'Nyarugenge, Kigali, Rwanda');
    });

    test('handles missing coordinates gracefully', () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'name': 'Unknown Place',
        'display_name': 'Unknown Place',
      });

      expect(result.primaryText, 'Unknown Place');
      expect(result.hasCoordinates, isFalse);
      expect(result.latitude, isNull);
      expect(result.longitude, isNull);
    });

    test('handles empty display_name', () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'display_name': '',
        'lat': '0.0',
        'lon': '0.0',
        'address': <String, dynamic>{},
      });

      // Should produce an empty primary text since no candidates match.
      expect(result.primaryText, isEmpty);
    });

    test('preserves Nominatim place_id', () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'name': 'Test',
        'display_name': 'Test',
        'lat': '-1.0',
        'lon': '30.0',
        'place_id': '12345',
      });

      expect(result.placeId, '12345');
    });
  });

  group('PlaceSearchResult.fromMapsGatewayJson', () {
    test('derives readable labels from maps gateway payloads', () {
      final result = PlaceSearchResult.fromMapsGatewayJson(<String, dynamic>{
        'placeId': 'ChIJ123',
        'label': 'Kigali Heights, KN 5 Road, Kigali, Rwanda',
        'primaryText': 'Kigali Heights',
        'secondaryText': 'KN 5 Road, Kigali, Rwanda',
        'position': <String, dynamic>{
          'latitude': -1.94995,
          'longitude': 30.08242,
        },
      });

      expect(result.placeId, 'ChIJ123');
      expect(result.label, 'Kigali Heights, KN 5 Road, Kigali, Rwanda');
      expect(result.primaryText, 'Kigali Heights');
      expect(result.secondaryText, 'KN 5 Road, Kigali, Rwanda');
      expect(result.latitude, closeTo(-1.94995, 0.00001));
      expect(result.longitude, closeTo(30.08242, 0.00001));
    });

    test('handles missing position gracefully', () {
      final result = PlaceSearchResult.fromMapsGatewayJson(<String, dynamic>{
        'placeId': 'ChIJ456',
        'label': 'Some Place',
        'primaryText': 'Some Place',
      });

      expect(result.hasCoordinates, isFalse);
      expect(result.placeId, 'ChIJ456');
      expect(result.primaryText, 'Some Place');
    });

    test('falls back to label when primaryText is empty', () {
      final result = PlaceSearchResult.fromMapsGatewayJson(<String, dynamic>{
        'placeId': 'ChIJ789',
        'label': 'Fallback Label',
        'primaryText': '',
      });

      expect(result.primaryText, 'Fallback Label');
    });

    test('constructs label from parts when label is missing', () {
      final result = PlaceSearchResult.fromMapsGatewayJson(<String, dynamic>{
        'placeId': 'ChIJABC',
        'primaryText': 'Primary',
        'secondaryText': 'Secondary',
      });

      expect(result.label, 'Primary, Secondary');
    });
  });

  group('PlaceSearchResult getters', () {
    test('hasCoordinates is true when position is present', () {
      const result = PlaceSearchResult(
        label: 'Test',
        position: GeoPoint(latitude: -1.95, longitude: 30.06),
      );

      expect(result.hasCoordinates, isTrue);
      expect(result.latitude, -1.95);
      expect(result.longitude, 30.06);
    });

    test('hasCoordinates is false when position is null', () {
      const result = PlaceSearchResult(label: 'Test');

      expect(result.hasCoordinates, isFalse);
      expect(result.latitude, isNull);
      expect(result.longitude, isNull);
    });
  });
}

