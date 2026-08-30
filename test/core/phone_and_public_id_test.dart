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

  test('keeps Rwanda-only normalization for local phone helper paths', () {
    expect(
      () => PhoneNormalizer.normalizeRwanda('+14155550100'),
      throwsFormatException,
    );
  });

  test('normalizes international WhatsApp phone numbers to E.164', () {
    expect(
      PhoneNormalizer.normalizeInternational('+1 (415) 555-0100'),
      '+14155550100',
    );
    expect(
      PhoneNormalizer.normalizeInternational('00250788123456'),
      '+250788123456',
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
