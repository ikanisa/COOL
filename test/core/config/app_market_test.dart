import 'package:cool_app/core/config/app_market.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMarket (Rwanda-only lock)', () {
    test('country is RW', () {
      expect(AppMarket.countryCode, 'RW');
    });

    test('currency is RWF', () {
      expect(AppMarket.country.currencyCode, 'RWF');
    });

    test('language is English', () {
      expect(AppMarket.languageCode, 'en');
    });

    test('dial code is +250', () {
      expect(AppMarket.country.dialCode, '+250');
    });
  });
}
