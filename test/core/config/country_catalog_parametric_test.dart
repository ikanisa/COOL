import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';

/// Parameterized tests for country phone validation metadata.
///
/// Every country with validation metadata must pass these invariants:
/// 1. Example national number parses successfully
/// 2. Example E.164 number parses successfully
/// 3. Example national → E.164 round-trip matches
/// 4. Invalid numbers are rejected
void main() {
  final countriesWithValidation = CoolCountryCatalog.all
      .where(
        (c) =>
            c.mobileNationalNumberPattern != null &&
            c.mobileExampleNational != null &&
            c.mobileExampleE164 != null,
      )
      .toList(growable: false);

  // Sanity: make sure we actually test countries
  test('At least 12 countries have full validation metadata', () {
    expect(
      countriesWithValidation.length,
      greaterThanOrEqualTo(12),
      reason:
          'Expected ≥ 12 countries with validation, got ${countriesWithValidation.length}',
    );
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
          // A clearly invalid number: too short and wrong prefix
          expect(country.isValidPhoneNumber('123'), isFalse);
          // All zeros should not match any valid mobile pattern
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
            // Strip leading zero for patterns that allow optional zero
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

  group('Countries without leading zero in E.164', () {
    // For countries where the national number starts with 0,
    // the E.164 form should strip the leading 0 — UNLESS the
    // country's E.164 example shows it is intentionally kept.
    final countriesWithLeadingZero = countriesWithValidation.where((c) {
      if (!c.mobileExampleNational!.startsWith('0')) return false;
      // If the E.164 example itself has dial code + 0, this country keeps it
      final dialDigits = c.dialCode.replaceFirst('+', '');
      final nationalInE164 = c.mobileExampleE164!
          .replaceFirst('+', '')
          .substring(dialDigits.length);
      return !nationalInE164.startsWith('0');
    });

    for (final country in countriesWithLeadingZero) {
      test(
        '${country.isoCode}: strips leading zero in E.164',
        () {
          final e164 = country.buildE164Phone(country.mobileExampleNational!);
          // E.164 should start with + and the dial code, NOT "+<dialCode>0..."
          expect(
            e164.startsWith('${country.dialCode}0'),
            isFalse,
            reason:
                '${country.isoCode}: E.164 should strip leading zero from national number',
          );
        },
      );
    }
  });

  group('Dial code prefix is not duplicated in E.164', () {
    for (final country in countriesWithValidation) {
      test(
        '${country.isoCode}: no double dial code',
        () {
          // If input already has dial code, should not double it
          final withDialCode =
              '${country.dialCode}${country.mobileExampleNational!.replaceFirst(RegExp(r'^0'), '')}';
          final e164 = country.buildE164Phone(withDialCode);
          final dialDigits = country.dialCode.replaceFirst('+', '');
          final nationalPart = e164.replaceFirst('+', '').substring(
            dialDigits.length,
          );
          // National part should NOT start with the dial code again
          expect(
            nationalPart.startsWith(dialDigits),
            isFalse,
            reason:
                '${country.isoCode}: dial code was duplicated in E.164 result',
          );
        },
      );
    }
  });
}
