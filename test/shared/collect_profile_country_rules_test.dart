import 'package:collect_app/shared/models/collect_models.dart';
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
}
