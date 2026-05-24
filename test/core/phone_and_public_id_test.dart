import 'dart:math';

import 'package:collect_app/core/security/phone_normalizer.dart';
import 'package:collect_app/core/security/public_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes Rwanda phone numbers to E.164', () {
    expect(PhoneNormalizer.normalizeRwanda('0788 123 456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('788123456'), '+250788123456');
    expect(PhoneNormalizer.normalizeRwanda('+250788123456'), '+250788123456');
  });

  test('rejects non-Rwanda phone numbers', () {
    expect(
      () => PhoneNormalizer.normalizeRwanda('+14155550100'),
      throwsFormatException,
    );
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
