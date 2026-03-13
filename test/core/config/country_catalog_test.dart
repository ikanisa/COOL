import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';

void main() {
  group('CoolCountryCatalog', () {
    test('resolves configured country aliases', () {
      expect(
        CoolCountryCatalog.resolve(country: 'Congo Kinshasa').isoCode,
        'CD',
      );
      expect(
        CoolCountryCatalog.resolve(country: "Cote d'Ivoire").isoCode,
        'CI',
      );
    });
  });

  group('CoolCountry.buildE164Phone', () {
    test('strips local trunk zero when the country E.164 form drops it', () {
      final ghana = CoolCountryCatalog.resolve(country: 'GH');

      expect(ghana.buildE164Phone('0231234567'), '+233231234567');
    });

    test('preserves NSN leading zero when the country E.164 keeps it', () {
      final benin = CoolCountryCatalog.resolve(country: 'BJ');

      expect(benin.buildE164Phone('0195123456'), '+2290195123456');
    });

    test('accepts mixed-length DRC phone recipients', () {
      final drc = CoolCountryCatalog.resolve(country: 'CD');

      expect(drc.buildE164Phone('8812345'), '+2438812345');
    });
  });

  group('CoolCountry.normalizeNationalPhone', () {
    test('converts Rwanda E.164 numbers to local storage format', () {
      final rwanda = CoolCountryCatalog.resolve(country: 'RW');

      expect(rwanda.normalizeNationalPhone('+250788767816'), '0788767816');
    });

    test('keeps countries without a trunk zero in local format', () {
      final botswana = CoolCountryCatalog.resolve(country: 'BW');

      expect(botswana.normalizeNationalPhone('+26771123456'), '71123456');
    });
  });

  group('CoolCountry.buildUssdCode', () {
    test('builds Benin phone route from a stored E.164 number', () {
      final benin = CoolCountryCatalog.resolve(country: 'BJ');

      expect(
        benin.buildUssdCode(recipientMomo: '+2290195123456', amount: 10000),
        '*400*1*195123456*10000#',
      );
    });

    test('keeps Rwanda phone and merchant-code routes separate', () {
      final rwanda = CoolCountryCatalog.resolve(country: 'RW');

      expect(
        rwanda.buildUssdCode(recipientMomo: '0720123456', amount: 5000),
        '*182*1*1*720123456*5000#',
      );
      expect(
        rwanda.buildUssdCode(
          recipientMomo: '123456',
          amount: 5000,
          recipientType: MomoRecipientType.code,
        ),
        '*182*8*1*123456*5000#',
      );
    });

    test('rejects merchant-code routes for countries without code support', () {
      final ghana = CoolCountryCatalog.resolve(country: 'GH');

      expect(
        () => ghana.buildUssdCode(
          recipientMomo: '123456',
          amount: 5000,
          recipientType: MomoRecipientType.code,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('supports country-specific USSD prefixes such as Tanzania', () {
      final tanzania = CoolCountryCatalog.resolve(country: 'TZ');

      expect(
        tanzania.buildUssdCode(recipientMomo: '0621234567', amount: 5000),
        '*150*00*1*621234567*5000#',
      );
    });
  });
}
