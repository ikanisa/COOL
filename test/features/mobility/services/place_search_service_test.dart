import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/mobility/services/place_search_service.dart';

void main() {
  test('PlaceSearchResult derives readable labels from Nominatim payloads', () {
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

  test(
    'PlaceSearchResult falls back to address fragments when name is absent',
    () {
      final result = PlaceSearchResult.fromNominatimJson(<String, dynamic>{
        'display_name': 'Nyamirambo, Nyarugenge, Kigali, Rwanda',
        'lat': '-1.9753',
        'lon': '30.0394',
        'address': <String, dynamic>{'suburb': 'Nyamirambo', 'city': 'Kigali'},
      });

      expect(result.primaryText, 'Nyamirambo');
      expect(result.secondaryText, 'Nyarugenge, Kigali, Rwanda');
    },
  );
}
