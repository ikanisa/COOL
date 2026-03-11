import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses minimal valid JSON', () {
      final json = {
        'id': 'abc123',
        'phone': '+250788000000',
        'full_name': 'Jean Bosco',
        'momo_number': '0788000000',
        'momo_provider': 'mtn_momo_rw',
        'country': 'RW',
        'language_code': 'en',
        'is_driver': false,
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'abc123');
      expect(profile.phone, '+250788000000');
      expect(profile.fullName, 'Jean Bosco');
      expect(profile.momoNumber, '0788000000');
      expect(profile.country, 'RW');
      expect(profile.languageCode, 'en');
      expect(profile.isDriver, false);
      expect(profile.vehicleType, isNull);
      expect(profile.createdAt, isNull);
    });

    test('falls back to "name" key when "full_name" is missing', () {
      final json = {
        'id': 'x1',
        'phone': '+250788111111',
        'name': 'Fallback Name',
        'momo_number': '0788111111',
        'momo_provider': '',
        'country': '',
        'is_driver': false,
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.fullName, 'Fallback Name');
    });

    test('parses is_driver as string "true"', () {
      final json = {
        'id': 'x2',
        'phone': '+250788222222',
        'full_name': 'Driver Test',
        'momo_number': '0788222222',
        'momo_provider': '',
        'country': '',
        'is_driver': 'true',
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.isDriver, true);
    });

    test('parses is_driver as int 1', () {
      final json = {
        'id': 'x3',
        'phone': '+250788333333',
        'full_name': 'Driver Num',
        'momo_number': '0788333333',
        'momo_provider': '',
        'country': '',
        'is_driver': 1,
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.isDriver, true);
    });

    test('handles null/missing values gracefully', () {
      final json = <String, dynamic>{};

      final profile = UserProfile.fromJson(json);

      expect(profile.id, '');
      expect(profile.phone, '');
      expect(profile.fullName, '');
      expect(profile.momoNumber, '');
      expect(profile.country, '');
      expect(profile.languageCode, 'en');
      expect(profile.isDriver, false);
    });

    test('parses ISO 8601 date strings', () {
      final json = {
        'id': 'x4',
        'phone': '+250788444444',
        'full_name': 'Date Test',
        'momo_number': '0788444444',
        'momo_provider': '',
        'country': '',
        'is_driver': false,
        'created_at': '2025-01-15T10:30:00.000Z',
        'updated_at': '2025-06-01T12:00:00.000Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.createdAt, isNotNull);
      expect(profile.createdAt!.year, 2025);
      expect(profile.createdAt!.month, 1);
      expect(profile.updatedAt, isNotNull);
    });

    test('falls back to "language" key when "language_code" is missing', () {
      final json = {
        'id': 'x5',
        'phone': '+250788555555',
        'full_name': 'Lang Test',
        'momo_number': '0788555555',
        'momo_provider': '',
        'country': '',
        'is_driver': false,
        'language': 'rw',
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.languageCode, 'rw');
    });
  });

  group('UserProfile.toJson', () {
    test('roundtrips through fromJson → toJson', () {
      final original = {
        'id': 'roundtrip-id',
        'phone': '+250788000000',
        'full_name': 'Roundtrip User',
        'momo_number': '0788000000',
        'momo_provider': 'mtn_momo_rw',
        'country': 'RW',
        'language_code': 'en',
        'is_driver': false,
      };

      final profile = UserProfile.fromJson(original);
      final json = profile.toJson();

      expect(json['id'], 'roundtrip-id');
      expect(json['phone'], '+250788000000');
      expect(json['full_name'], 'Roundtrip User');
      expect(json['is_driver'], false);
    });

    test('removes null values from output', () {
      final profile = UserProfile.fromJson({
        'id': 'strip-null',
        'phone': '+250788666666',
        'full_name': 'Strip Null',
        'momo_number': '0788666666',
        'momo_provider': '',
        'country': '',
        'is_driver': false,
      });

      final json = profile.toJson();

      expect(json.containsKey('vehicle_type'), isFalse);
      expect(json.containsKey('created_at'), isFalse);
      expect(json.containsKey('updated_at'), isFalse);
    });
  });

  group('UserProfile.copyWith', () {
    test('preserves unchanged fields', () {
      final profile = UserProfile.fromJson({
        'id': 'copy-id',
        'phone': '+250788777777',
        'full_name': 'Copy Test',
        'momo_number': '0788777777',
        'momo_provider': 'mtn_momo_rw',
        'country': 'RW',
        'language_code': 'en',
        'is_driver': true,
      });

      final copied = profile.copyWith(fullName: 'New Name');

      expect(copied.fullName, 'New Name');
      expect(copied.id, 'copy-id');
      expect(copied.phone, '+250788777777');
      expect(copied.isDriver, true);
    });
  });
}
