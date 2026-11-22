import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/core/security/hash_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile country rules admit Rwanda and RWF only', () {
    expect(CollectProfileCountryRules.isSupportedCountry('RW'), isTrue);
    expect(CollectProfileCountryRules.isSupportedCountry('GB'), isFalse);
    expect(CollectProfileCountryRules.currencyForCountry('RW'), 'RWF');
    expect(CollectProfileCountryRules.currencyForCountry('GB'), 'XXX');
    expect(
      CollectProfileCountryRules.inferCountryCodeFromPhone('+250788123456'),
      'RW',
    );
    expect(
      CollectProfileCountryRules.inferCountryCodeFromPhone('+447700900123'),
      isEmpty,
    );
  });

  test('only a complete Rwanda MoMo profile is ready', () {
    final ready = CollectProfile.fromJson(const {
      'id': 'user-1',
      'public_id': '123456',
      'whatsapp_phone': '+250788123456',
      'country_code': 'RW',
      'currency_code': 'RWF',
      'momo_provider': 'mtn_momo',
      'momo_number': '0788123456',
    });
    expect(ready.isComplete, isTrue);
    expect(ready.copyWith(countryCode: 'GB').isComplete, isFalse);
    expect(ready.copyWith(currencyCode: 'EUR').isComplete, isFalse);
    expect(ready.copyWith(momoNumber: '').isComplete, isFalse);
  });

  test('missing MoMo data does not become the sign-in phone', () {
    final data = <String, dynamic>{
      'id': 'user-1',
      'public_id': '123456',
      'whatsapp_phone': '+250788123456',
      'country_code': 'RW',
      'currency_code': 'RWF',
      'momo_provider': 'mtn_momo',
    };
    for (final value in [null, '']) {
      final profile = CollectProfile.fromJson({...data, 'momo_number': value});
      expect(profile.momoNumber, isEmpty);
      expect(profile.isComplete, isFalse);
    }
    final omitted = CollectProfile.fromJson(data);
    expect(omitted.momoNumber, isEmpty);
    expect(omitted.isComplete, isFalse);

    final different = CollectProfile.fromJson({
      ...data,
      'momo_number': '0788999000',
    });
    expect(different.momoNumber, '0788999000');
    expect(different.whatsappPhone, '+250788123456');
    expect(different.isComplete, isTrue);
  });

  test(
    'compact international account forms pass readiness without rewriting',
    () {
      final data = <String, dynamic>{
        'id': 'user-1',
        'public_id': '123456',
        'whatsapp_phone': '+250788123456',
        'country_code': 'RW',
        'currency_code': 'RWF',
        'momo_provider': 'mtn_momo',
      };
      for (final number in ['0788999000', '+250788999000', '250788999000']) {
        final input = {...data, 'momo_number': number};
        final profile = CollectProfile.fromJson(input);
        expect(profile.momoNumber, number);
        expect(input['momo_number'], number);
        expect(profile.whatsappPhone, '+250788123456');
        expect(profile.isComplete, isTrue);
        expect(
          HashUtils.phoneHash(profile.momoNumber),
          HashUtils.phoneHash('0788999000'),
        );
        expect(profile.copyWith(momoPayCode: '0012').momoNumber, number);
      }
      final airtel = CollectProfile.fromJson({
        ...data,
        'momo_provider': 'airtel_money',
        'momo_number': '+250738123456',
      });
      expect(airtel.momoNumber, '+250738123456');
      expect(airtel.isComplete, isTrue);
      final unsupportedAirtel = CollectProfile.fromJson({
        ...data,
        'momo_provider': 'airtel_money',
        'momo_number': '00250738123456',
      });
      expect(unsupportedAirtel.momoNumber, '00250738123456');
      expect(unsupportedAirtel.isComplete, isFalse);
    },
  );

  test(
    'malformed and unsupported representations stay incomplete and intact',
    () {
      final data = <String, dynamic>{
        'id': 'user-1',
        'public_id': '123456',
        'whatsapp_phone': '+250788123456',
        'country_code': 'RW',
        'currency_code': 'RWF',
        'momo_provider': 'mtn_momo',
      };
      for (final number in [
        'prefix+250788999000',
        '+250788999000x',
        '++250788999000',
        '+251788999000',
        '+250758999000',
        '00250788999000',
        '00250738123456',
        '00250+788999000',
        '+250 788 999 000',
        '788999000',
      ]) {
        final profile = CollectProfile.fromJson({
          ...data,
          'momo_number': number,
        });
        expect(profile.momoNumber, number);
        expect(profile.isComplete, isFalse);
      }
      expect(
        () => CollectProfile.fromJson({...data, 'momo_number': 123}),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test(
    'international number does not bypass provider or other profile checks',
    () {
      final data = <String, dynamic>{
        'id': 'user-1',
        'public_id': '123456',
        'whatsapp_phone': '+250788123456',
        'country_code': 'RW',
        'currency_code': 'RWF',
        'momo_provider': 'airtel_money',
        'momo_number': '+250788999000',
      };
      expect(CollectProfile.fromJson(data).isComplete, isFalse);
      expect(
        CollectProfile.fromJson({...data, 'momo_provider': null}).isComplete,
        isFalse,
      );
      expect(
        CollectProfile.fromJson({
          ...data,
          'momo_provider': 'mtn_momo',
          'currency_code': 'EUR',
        }).isComplete,
        isFalse,
      );
    },
  );
}
