import 'dart:convert';
import 'dart:io';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('country rules provide current local currencies and Europe flags', () {
    expect(CollectProfileCountryRules.currencyForCountry('RW'), 'RWF');
    expect(CollectProfileCountryRules.currencyForCountry('GB'), 'GBP');
    expect(CollectProfileCountryRules.currencyForCountry('DE'), 'EUR');
    expect(CollectProfileCountryRules.currencyForCountry('US'), 'USD');
    expect(CollectProfileCountryRules.currencyForCountry('BG'), 'EUR');
    expect(CollectProfileCountryRules.currencyForCountry('ZW'), 'ZWG');
    expect(CollectProfileCountryRules.isEuropeanCountry('MT'), isTrue);
    expect(CollectProfileCountryRules.isEuropeanCountry('CY'), isTrue);
    expect(CollectProfileCountryRules.isEuropeanCountry('AL'), isFalse);
    expect(CollectProfileCountryRules.isEuropeanCountry('RW'), isFalse);
  });

  test('picker, app, and database country rules stay aligned', () {
    final migration = File(
      'supabase/migrations/20260828100000_profile_country_session_independence.sql',
    ).readAsStringSync();
    final currencyJson = RegExp(
      r'\$country_currency\$(\{.*?\})\$country_currency\$',
      dotAll: true,
    ).firstMatch(migration)?.group(1);
    expect(currencyJson, isNotNull);
    final databaseCurrencies =
        jsonDecode(currencyJson!) as Map<String, dynamic>;
    final europeSql = RegExp(
      r'entry\.country_code = any\(array\[(.*?)\]::text\[\]\)',
      dotAll: true,
    ).firstMatch(migration)?.group(1);
    expect(europeSql, isNotNull);
    final databaseEurope = {
      for (final match in RegExp(r"'([A-Z]{2})'").allMatches(europeSql!))
        match.group(1)!,
    };
    final pickerCountries = CountryService().getAll();

    expect(databaseCurrencies, hasLength(pickerCountries.length));
    for (final country in pickerCountries) {
      final code = country.countryCode;
      expect(CollectProfileCountryRules.isSupportedCountry(code), isTrue);
      expect(
        CollectProfileCountryRules.currencyForCountry(code),
        databaseCurrencies[code],
        reason: code,
      );
      expect(
        CollectProfileCountryRules.isEuropeanCountry(code),
        databaseEurope.contains(code),
        reason: code,
      );
    }
  });

  test('WhatsApp calling code is only an initial country suggestion', () {
    expect(
      CollectProfileCountryRules.inferCountryCodeFromPhone('+250788123456'),
      'RW',
    );
    expect(
      CollectProfileCountryRules.inferCountryCodeFromPhone('+447700900123'),
      'GB',
    );
  });

  test(
    'profile JSON remains backward compatible and derives a local default',
    () {
      final profile = CollectProfile.fromJson(const {
        'id': 'user-1',
        'public_id': '123456',
        'whatsapp_phone': '+250788123456',
      });

      expect(profile.countryCode, 'RW');
      expect(profile.currencyCode, 'RWF');
      expect(profile.whatsappPhone, '+250788123456');
      expect(profile.isComplete, isFalse);
    },
  );

  test('European profile completion includes full Revolut details', () {
    final incomplete = CollectProfile.fromJson(const {
      'id': 'user-2',
      'public_id': '654321',
      'whatsapp_phone': '+250788123456',
      'display_name': 'Jean Bosco',
      'country_code': 'GB',
      'currency_code': 'GBP',
    });
    final complete = incomplete.copyWith(
      revolutLink: 'https://revolut.me/jeanbosco',
      revolutAccount: 'Personal EUR account',
    );
    final mismatchedCurrency = complete.copyWith(currencyCode: 'RWF');

    expect(incomplete.isEuropean, isTrue);
    expect(incomplete.isComplete, isFalse);
    expect(complete.isComplete, isTrue);
    expect(mismatchedCurrency.isComplete, isFalse);
  });
}
