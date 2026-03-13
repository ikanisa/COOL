import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/core/utils/phone_validator.dart';
import 'package:cool_app/core/config/country_catalog.dart';

void main() {
  group('PhoneValidator', () {
    group('toRwandanLocal', () {
      test('strips +250 prefix', () {
        expect(PhoneValidator.toRwandanLocal('+250781234567'), '781234567');
      });

      test('strips 250 prefix', () {
        expect(PhoneValidator.toRwandanLocal('250781234567'), '781234567');
      });

      test('strips leading 0', () {
        expect(PhoneValidator.toRwandanLocal('0781234567'), '781234567');
      });

      test('handles 9-digit local', () {
        expect(PhoneValidator.toRwandanLocal('781234567'), '781234567');
      });

      test('returns null for short numbers', () {
        expect(PhoneValidator.toRwandanLocal('78123'), null);
      });

      test('strips spaces and dashes', () {
        expect(PhoneValidator.toRwandanLocal('+250 78 123 4567'), '781234567');
      });
    });

    group('isValidRwandanMobile', () {
      test('accepts MTN 078', () {
        expect(PhoneValidator.isValidRwandanMobile('0781234567'), true);
      });

      test('accepts MTN 079', () {
        expect(PhoneValidator.isValidRwandanMobile('+250791234567'), true);
      });

      test('accepts Airtel 072', () {
        expect(PhoneValidator.isValidRwandanMobile('0721234567'), true);
      });

      test('accepts Airtel 073', () {
        expect(PhoneValidator.isValidRwandanMobile('731234567'), true);
      });

      test('accepts 075 (legacy)', () {
        expect(PhoneValidator.isValidRwandanMobile('751234567'), true);
      });

      test('rejects 076 prefix', () {
        expect(PhoneValidator.isValidRwandanMobile('761234567'), false);
      });

      test('rejects short number', () {
        expect(PhoneValidator.isValidRwandanMobile('78123'), false);
      });

      test('rejects empty', () {
        expect(PhoneValidator.isValidRwandanMobile(''), false);
      });
    });

    group('isValidMtnRwanda', () {
      test('078 is MTN', () {
        expect(PhoneValidator.isValidMtnRwanda('0781234567'), true);
      });

      test('079 is MTN', () {
        expect(PhoneValidator.isValidMtnRwanda('+250791234567'), true);
      });

      test('072 is not MTN', () {
        expect(PhoneValidator.isValidMtnRwanda('0721234567'), false);
      });
    });

    group('isValidAirtelRwanda', () {
      test('072 is Airtel', () {
        expect(PhoneValidator.isValidAirtelRwanda('0721234567'), true);
      });

      test('073 is Airtel', () {
        expect(PhoneValidator.isValidAirtelRwanda('731234567'), true);
      });

      test('078 is not Airtel', () {
        expect(PhoneValidator.isValidAirtelRwanda('0781234567'), false);
      });
    });

    group('detectRwandanProvider', () {
      test('detects MTN', () {
        expect(
          PhoneValidator.detectRwandanProvider('+250781234567'),
          RwandaProvider.mtn,
        );
      });

      test('detects Airtel', () {
        expect(
          PhoneValidator.detectRwandanProvider('0721234567'),
          RwandaProvider.airtel,
        );
      });

      test('detects unknown valid prefix', () {
        expect(
          PhoneValidator.detectRwandanProvider('751234567'),
          RwandaProvider.unknown,
        );
      });

      test('returns null for invalid', () {
        expect(PhoneValidator.detectRwandanProvider('761234567'), null);
      });

      test('returns null for garbage', () {
        expect(PhoneValidator.detectRwandanProvider('abc'), null);
      });
    });

    group('formatRwandanDisplay', () {
      test('formats correctly', () {
        expect(
          PhoneValidator.formatRwandanDisplay('+250781234567'),
          '+250 781 234 567',
        );
      });

      test('returns original for invalid', () {
        expect(PhoneValidator.formatRwandanDisplay('123'), '123');
      });
    });

    group('validateMomoNumber', () {
      test('valid RW number', () {
        expect(PhoneValidator.validateMomoNumber('0781234567', 'RW'), null);
      });

      test('invalid RW number', () {
        expect(
          PhoneValidator.validateMomoNumber('0661234567', 'RW'),
          isNotNull,
        );
      });

      test('empty returns error', () {
        expect(PhoneValidator.validateMomoNumber('', 'RW'), isNotNull);
      });
    });

    group('validateMomoCode', () {
      test('accepts 4-digit code', () {
        expect(PhoneValidator.validateMomoCode('1234'), null);
      });

      test('accepts 8-digit code', () {
        expect(PhoneValidator.validateMomoCode('12345678'), null);
      });

      test('empty is valid (optional)', () {
        expect(PhoneValidator.validateMomoCode(''), null);
      });

      test('rejects 3-digit code', () {
        expect(PhoneValidator.validateMomoCode('123'), isNotNull);
      });

      test('accepts 9-digit Rwanda code', () {
        expect(PhoneValidator.validateMomoCode('123456789'), null);
      });

      test('rejects letters', () {
        expect(PhoneValidator.validateMomoCode('12ab'), isNotNull);
      });

      test('accepts Rwanda merchant codes under country rules', () {
        final rwanda = CoolCountryCatalog.resolve(country: 'RW');

        expect(
          PhoneValidator.validateMomoCode(
            '123456',
            country: rwanda,
            required: true,
          ),
          null,
        );
      });

      test('rejects codes longer than Rwanda rules allow', () {
        final rwanda = CoolCountryCatalog.resolve(country: 'RW');

        expect(
          PhoneValidator.validateMomoCode(
            '1234567890',
            country: rwanda,
            required: true,
          ),
          contains('valid merchant code'),
        );
      });
    });

    group('shouldAutoPopulateMomo', () {
      test('MTN RW → true', () {
        expect(
          PhoneValidator.shouldAutoPopulateMomo('+250781234567', 'RW'),
          true,
        );
      });

      test('Airtel RW → false', () {
        expect(
          PhoneValidator.shouldAutoPopulateMomo('+250721234567', 'RW'),
          false,
        );
      });

      test('non-RW country → false', () {
        expect(
          PhoneValidator.shouldAutoPopulateMomo('+256781234567', 'UG'),
          false,
        );
      });
    });

    group('buildOtpE164Phone', () {
      final rwanda = CoolCountryCatalog.resolve(country: 'RW');

      test('accepts Rwanda local numbers without +', () {
        expect(
          PhoneValidator.buildOtpE164Phone('0781234567', rwanda),
          '+250781234567',
        );
      });

      test('accepts global WhatsApp numbers with +', () {
        expect(
          PhoneValidator.buildOtpE164Phone('+256781234567', rwanda),
          '+256781234567',
        );
      });

      test('accepts global WhatsApp numbers with 00 prefix', () {
        expect(
          PhoneValidator.buildOtpE164Phone('00256781234567', rwanda),
          '+256781234567',
        );
      });

      test('rejects non-Rwanda E.164 input without +', () {
        expect(
          () => PhoneValidator.buildOtpE164Phone('256781234567', rwanda),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Use + for full E.164 WhatsApp numbers',
            ),
          ),
        );
      });
    });
  });
}
