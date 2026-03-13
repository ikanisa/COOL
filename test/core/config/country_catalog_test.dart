import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';

void main() {
  group('CoolCountryCatalog — Rwanda-only invariants', () {
    test('all contains exactly one country', () {
      expect(CoolCountryCatalog.all, hasLength(1));
    });

    test('defaultCountry is Rwanda', () {
      expect(CoolCountryCatalog.defaultCountry.isoCode, 'RW');
      expect(CoolCountryCatalog.defaultCountry.currencyCode, 'RWF');
      expect(CoolCountryCatalog.defaultCountry.dialCode, '+250');
    });

    test('resolve always returns Rwanda', () {
      expect(CoolCountryCatalog.resolve().isoCode, 'RW');
      expect(CoolCountryCatalog.resolve(country: 'RW').isoCode, 'RW');
      // Unknown country codes fall back to Rwanda
      expect(CoolCountryCatalog.resolve(country: 'GH').isoCode, 'RW');
      expect(CoolCountryCatalog.resolve(country: 'MT').isoCode, 'RW');
    });

    test('normalizeCountryCode defaults to RW', () {
      expect(CoolCountryCatalog.normalizeCountryCode(null), 'RW');
      expect(CoolCountryCatalog.normalizeCountryCode(''), 'RW');
      expect(CoolCountryCatalog.normalizeCountryCode('RW'), 'RW');
    });
  });

  group('CoolCountry.buildE164Phone — Rwanda', () {
    final rwanda = CoolCountryCatalog.defaultCountry;

    test('converts national format to E.164', () {
      expect(rwanda.buildE164Phone('0781234567'), '+250781234567');
    });

    test('passes through valid E.164 unchanged', () {
      expect(rwanda.buildE164Phone('+250781234567'), '+250781234567');
    });

    test('strips local trunk zero', () {
      expect(rwanda.buildE164Phone('0721234567'), '+250721234567');
    });

    test('rejects invalid numbers', () {
      expect(
        () => rwanda.buildE164Phone('0401234567'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CoolCountry.normalizeNationalPhone — Rwanda', () {
    final rwanda = CoolCountryCatalog.defaultCountry;

    test('converts E.164 to local storage format', () {
      expect(rwanda.normalizeNationalPhone('+250788767816'), '0788767816');
    });

    test('keeps national format unchanged', () {
      expect(rwanda.normalizeNationalPhone('0788767816'), '0788767816');
    });
  });

  group('CoolCountry.buildUssdCode — Rwanda', () {
    final rwanda = CoolCountryCatalog.defaultCountry;

    test('builds phone-number payment route', () {
      expect(
        rwanda.buildUssdCode(recipientMomo: '0720123456', amount: 5000),
        '*182*1*1*720123456*5000#',
      );
    });

    test('builds merchant-code payment route', () {
      expect(
        rwanda.buildUssdCode(
          recipientMomo: '123456',
          amount: 5000,
          recipientType: MomoRecipientType.code,
        ),
        '*182*8*1*123456*5000#',
      );
    });

    test('supports merchant code validation', () {
      expect(rwanda.supportsMomoCode, isTrue);
      expect(rwanda.momoCodePattern, isNotNull);
    });
  });

  group('CoolCountry.normalizeMerchantCode — Rwanda', () {
    final rwanda = CoolCountryCatalog.defaultCountry;

    test('accepts valid codes in range', () {
      expect(rwanda.normalizeMerchantCode('123456'), '123456');
      expect(rwanda.normalizeMerchantCode('1234'), '1234');
    });

    test('rejects codes outside range', () {
      expect(
        () => rwanda.normalizeMerchantCode('12'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
