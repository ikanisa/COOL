import 'dart:math';

import 'package:collect_app/core/security/phone_normalizer.dart';
import 'package:collect_app/core/security/public_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes Rwanda MoMo phone numbers to E.164', () {
    expect(PhoneNormalizer.normalizeRwanda('0788 123 456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('788123456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('+250788123456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('00250788123456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('0723 123 456'), '+250723123456');
  });

  test('rejects foreign and non-MoMo phone numbers', () {
    for (final value in ['+14155550100', '+447400123456', '+250612345678']) {
      expect(
        () => PhoneNormalizer.normalizeRwanda(value),
        throwsFormatException,
      );
    }
  });

  test('generates unique 6-digit public IDs with retry', () {
    final generator = PublicIdGenerator(random: Random(7));
    final seen = <String>{};
    for (var i = 0; i < 1000; i++) {
      final id = generator.generate(seen);
      expect(id, matches(RegExp(r'^[0-9]{6}$')));
      expect(seen.add(id), isTrue);
    }
  });
}
