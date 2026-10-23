import 'package:collect_app/core/payments/rwanda_momo_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final prefix in ['078', '079', '072', '073']) {
    test('infers provider for complete $prefix numbers', () {
      final local = '${prefix}1234567';
      for (final input in [
        local,
        local.substring(1),
        '+250${local.substring(1)}',
        '00250${local.substring(1)}',
        '250${local.substring(1)}',
      ]) {
        final number = RwandaMomoNumber.parse(input);
        expect(number.localNumber, local);
        expect(
          number.provider,
          prefix == '078' || prefix == '079' ? 'mtn_momo' : 'airtel_money',
        );
      }
    });
  }
  test(
    'accepts spacing and rejects partial, foreign and non-mobile numbers',
    () {
      expect(
        RwandaMomoNumber.parse('+250 788 123 456').localNumber,
        '0788123456',
      );
      for (final input in [
        '',
        '078',
        '078812345',
        '07881234567',
        '+44 7700 900123',
        '0758123456',
        '0800123456',
        '0788123456abc',
        '0788123456.0',
      ]) {
        expect(
          () => RwandaMomoNumber.parse(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );
}
