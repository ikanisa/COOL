import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses minimal valid JSON', () {
      final json = {
        'id': 'abc123',
        'public_user_id': '123456',
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
      expect(profile.displayUserId, '123456');
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
      expect(profile.displayUserId, '000000');
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

    test('falls back to English when legacy language data is non-English', () {
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
      expect(profile.languageCode, 'en');
    });

    test('normalizes legacy E.164 momo numbers to local profile format', () {
      final json = {
        'id': 'x6',
        'phone': '+250788555555',
        'full_name': 'Legacy MoMo',
        'momo_number': '+250788767816',
        'momo_provider': 'mtn_rwanda',
        'country': 'RW',
        'language_code': 'en',
        'is_driver': false,
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.momoNumber, '0788767816');
    });

    test('parses code-based wallet routes without a phone recipient', () {
      final json = {
        'id': 'x7',
        'phone': '+256700123456',
        'full_name': 'Merchant Route',
        'momo_number': '',
        'momo_code': '445566',
        'momo_route_type': 'code',
        'momo_provider': 'mtn_ug',
        'country': 'UG',
        'language_code': 'en',
        'is_driver': false,
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.effectiveMomoRouteType, MomoRecipientType.code);
      expect(profile.momoRecipientValue, '445566');
      expect(profile.hasMomoRecipient, true);
      expect(profile.isProfileComplete, true);
      expect(profile.canShowMomoQr, isFalse);
    });

    test(
      'preserves a code default route when both wallet fields are stored',
      () {
        final json = {
          'id': 'x7b',
          'phone': '+250788000000',
          'full_name': 'Dual Route',
          'momo_number': '0788000000',
          'momo_code': '445566',
          'momo_route_type': 'code',
          'momo_provider': 'mtn_momo_rw',
          'country': 'RW',
          'language_code': 'en',
          'is_driver': false,
        };

        final profile = UserProfile.fromJson(json);

        expect(profile.momoNumber, '0788000000');
        expect(profile.momoCode, '445566');
        expect(profile.effectiveMomoRouteType, MomoRecipientType.code);
        expect(profile.momoRecipientValue, '445566');
        expect(profile.canShowMomoQr, isFalse);
      },
    );

    test('does not infer stored official identity from display fields', () {
      final profile = UserProfile.fromJson({
        'id': 'x8',
        'phone': '+250788888888',
        'full_name': 'Display Only',
        'momo_number': '0788888888',
        'momo_provider': 'mtn_momo_rw',
        'country': 'RW',
        'language_code': 'en',
        'is_driver': false,
      });

      expect(profile.officialName, isNull);
      expect(profile.officialPhone, isNull);
      expect(profile.hasOfficialIdentity, isFalse);
    });
  });

  group('UserProfile.toJson', () {
    test('roundtrips through fromJson → toJson', () {
      final original = {
        'id': 'roundtrip-id',
        'public_user_id': '654321',
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
      expect(json['public_user_id'], '654321');
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
      expect(json.containsKey('public_user_id'), isFalse);
      expect(json.containsKey('official_name'), isFalse);
      expect(json.containsKey('official_phone'), isFalse);
    });

    test('serializes the preferred wallet route type', () {
      const profile = UserProfile(
        id: 'route-json',
        phone: '+256700123456',
        fullName: 'Merchant Route',
        momoNumber: '',
        momoCode: '778899',
        momoRouteType: MomoRecipientType.code,
        momoProvider: 'mtn_ug',
        country: 'UG',
        languageCode: 'en',
        isDriver: false,
      );

      final json = profile.toJson();

      expect(json['momo_route_type'], 'code');
      expect(json['momo_code'], '778899');
    });

    test('does not persist empty official identity fields', () {
      const profile = UserProfile(
        id: 'identity-strip',
        phone: '+250788000001',
        fullName: 'Identity Strip',
        momoNumber: '0788000001',
        momoProvider: 'mtn_momo_rw',
        country: 'RW',
        languageCode: 'en',
        isDriver: false,
        officialName: '',
        officialPhone: '   ',
      );

      final json = profile.toJson();

      expect(json.containsKey('official_name'), isFalse);
      expect(json.containsKey('official_phone'), isFalse);
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

    test('keeps language pinned to English even when overridden', () {
      const profile = UserProfile(
        id: 'lang-pin',
        phone: '+250788777777',
        fullName: 'Copy Test',
        momoNumber: '0788777777',
        momoProvider: 'mtn_momo_rw',
        country: 'RW',
        languageCode: 'rw',
        isDriver: false,
      );

      final copied = profile.copyWith(languageCode: 'fr');

      expect(profile.languageCode, 'en');
      expect(copied.languageCode, 'en');
      expect(copied.toJson()['language_code'], 'en');
    });
  });
}
