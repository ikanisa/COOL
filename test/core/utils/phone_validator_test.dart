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

      test('generic country accepts 9+ digits', () {
        expect(PhoneValidator.validateMomoNumber('123456789', 'UG'), null);
      });

      test('generic country rejects short', () {
        expect(PhoneValidator.validateMomoNumber('12345', 'UG'), isNotNull);
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

      test('rejects 9-digit code', () {
        expect(PhoneValidator.validateMomoCode('123456789'), isNotNull);
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

      test('rejects merchant codes for countries without a code route', () {
        final ghana = CoolCountryCatalog.resolve(country: 'GH');

        expect(
          PhoneValidator.validateMomoCode(
            '123456',
            country: ghana,
            required: true,
          ),
          contains('not configured'),
        );
      });
    });

    group('cross-country MoMo validation', () {
      test('accepts Ghana local numbers and strips the trunk zero', () {
        expect(PhoneValidator.validateMomoNumber('0231234567', 'GH'), null);
      });

      test('preserves E.164 leading zero for Benin numbers', () {
        final benin = CoolCountryCatalog.resolve(country: 'BJ');

        expect(benin.buildE164Phone('0195123456'), '+2290195123456');
      });

      test('accepts DRC mixed-length mobile recipients', () {
        expect(PhoneValidator.validateMomoNumber('8812345', 'CD'), null);
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
  });
}
