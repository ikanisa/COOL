import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/app_market.dart';
import 'package:cool_app/core/config/country_catalog.dart';

/// Rwanda-only invariant tests.
///
/// These tests assert that the COOL app is locked to the
/// Rwandan market and will fail if multi-country support is
/// accidentally reintroduced.
void main() {
  group('App market invariants', () {
    test('countryCode is RW', () {
      expect(AppMarket.countryCode, 'RW');
    });

    test('languageCode is en', () {
      expect(AppMarket.languageCode, 'en');
    });

    test('currency is RWF', () {
      expect(AppMarket.country.currencyCode, 'RWF');
    });
  });

  group('Country catalog invariants', () {
    test('exactly one supported country', () {
      expect(CoolCountryCatalog.all, hasLength(1));
    });

    test('supported country is Rwanda', () {
      final country = CoolCountryCatalog.all.first;
      expect(country.isoCode, 'RW');
      expect(country.name, 'Rwanda');
      expect(country.dialCode, '+250');
      expect(country.currencyCode, 'RWF');
      expect(country.flagEmoji, '🇷🇼');
    });

    test('defaultCountry is Rwanda', () {
      expect(CoolCountryCatalog.defaultCountry.isoCode, 'RW');
    });

    test('resolve() always returns Rwanda', () {
      expect(CoolCountryCatalog.resolve().isoCode, 'RW');
      expect(CoolCountryCatalog.resolve(country: 'RW').isoCode, 'RW');
      expect(CoolCountryCatalog.resolve(country: 'XX').isoCode, 'RW');
      expect(CoolCountryCatalog.resolve(phone: '+250781234567').isoCode, 'RW');
    });

    test('Rwanda has MoMo code support', () {
      final rw = CoolCountryCatalog.defaultCountry;
      expect(rw.supportsMomoCode, isTrue);
      expect(rw.momoCodePattern, isNotNull);
      expect(rw.momoCodeExample, isNotNull);
    });
  });
}
