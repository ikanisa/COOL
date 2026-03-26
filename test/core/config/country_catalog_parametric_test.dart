import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';

/// Parameterized tests for country phone validation metadata.
///
/// Since the app is Rwanda-only, CoolCountryCatalog.all contains just Rwanda.
/// These tests verify:
/// 1. Rwanda has full validation metadata
/// 2. Example national number parses successfully
/// 3. Example E.164 number parses successfully
/// 4. Example national → E.164 round-trip matches
/// 5. Invalid numbers are rejected
void main() {
  final countriesWithValidation = CoolCountryCatalog.all
      .where(
        (c) =>
            c.mobileNationalNumberPattern != null &&
            c.mobileExampleNational != null &&
            c.mobileExampleE164 != null,
      )
      .toList(growable: false);

  // Rwanda-only: exactly 1 country with validation metadata
  test('Exactly 1 country has full validation metadata', () {
    expect(
      countriesWithValidation.length,
      equals(1),
      reason: 'Rwanda-only app: expected 1 country with validation',
    );
    expect(countriesWithValidation.first.isoCode, 'RW');
  });

  group('Country phone validation round-trips', () {
    for (final country in countriesWithValidation) {
      group('${country.flagEmoji} ${country.name} (${country.isoCode})', () {
        test('example national number is valid', () {
          expect(
            country.isValidPhoneNumber(country.mobileExampleNational!),
            isTrue,
            reason:
                '${country.isoCode}: ${country.mobileExampleNational} should be valid',
          );
        });

        test('example E.164 number is valid', () {
          expect(
            country.isValidPhoneNumber(country.mobileExampleE164!),
            isTrue,
            reason:
                '${country.isoCode}: ${country.mobileExampleE164} should be valid',
          );
        });

        test('national → E.164 round-trip matches', () {
          final e164 = country.buildE164Phone(country.mobileExampleNational!);
          expect(
            e164,
            equals(country.mobileExampleE164),
            reason:
                '${country.isoCode}: ${country.mobileExampleNational} → $e164, expected ${country.mobileExampleE164}',
          );
        });

        test('E.164 → E.164 is idempotent', () {
          final e164 = country.buildE164Phone(country.mobileExampleE164!);
          expect(
            e164,
            equals(country.mobileExampleE164),
            reason:
                '${country.isoCode}: E.164 input should return itself unchanged',
          );
        });

        test('invalid number is rejected', () {
          expect(country.isValidPhoneNumber('123'), isFalse);
          expect(country.isValidPhoneNumber('0000000000000'), isFalse);
        });

        test('mobilePossibleLengths are non-empty', () {
          expect(
            country.mobilePossibleLengths,
            isNotEmpty,
            reason:
                '${country.isoCode}: mobilePossibleLengths should not be empty',
          );
        });

        if (country.momoNumberLocalPattern != null) {
          test('momoNumberLocalPattern matches example national', () {
            final pattern = RegExp(country.momoNumberLocalPattern!);
            final national = country.mobileExampleNational!;
            expect(
              pattern.hasMatch(national),
              isTrue,
              reason:
                  '${country.isoCode}: momoNumberLocalPattern should match $national',
            );
          });
        }

        if (country.momoNumberE164Pattern != null) {
          test('momoNumberE164Pattern matches example E.164', () {
            final pattern = RegExp(country.momoNumberE164Pattern!);
            expect(
              pattern.hasMatch(country.mobileExampleE164!),
              isTrue,
              reason:
                  '${country.isoCode}: momoNumberE164Pattern should match ${country.mobileExampleE164}',
            );
          });
        }
      });
    }
  });

  group('Rwanda E.164 stripLeadingZero', () {
    final rwanda = countriesWithValidation.first;
    test('strips leading zero in E.164', () {
      final e164 = rwanda.buildE164Phone(rwanda.mobileExampleNational!);
      expect(
        e164.startsWith('${rwanda.dialCode}0'),
        isFalse,
        reason: 'RW: E.164 should strip leading zero from national number',
      );
    });
  });

  group('Rwanda dial code prefix is not duplicated', () {
    final rwanda = countriesWithValidation.first;
    test('no double dial code', () {
      final withDialCode =
          '${rwanda.dialCode}${rwanda.mobileExampleNational!.replaceFirst(RegExp(r'^0'), '')}';
      final e164 = rwanda.buildE164Phone(withDialCode);
      final dialDigits = rwanda.dialCode.replaceFirst('+', '');
      final nationalPart = e164
          .replaceFirst('+', '')
          .substring(dialDigits.length);
      expect(
        nationalPart.startsWith(dialDigits),
        isFalse,
        reason: 'RW: dial code was duplicated in E.164 result',
      );
    });
  });
}
