import 'package:collect_app/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in [null, 'en', 'fr', 'rw']) {
    test('exact maximum preserves all integer digits in locale $locale', () {
      final positive = formatRwf(9007199254740991, localeName: locale);
      final negative = formatRwf(-9007199254740991, localeName: locale);
      expect(positive.replaceAll(RegExp(r'\D'), ''), '9007199254740991');
      expect(negative.replaceAll(RegExp(r'\D'), ''), '9007199254740991');
      expect(negative, contains('-'));
      expect(positive, contains('RWF'));
    });
  }
  test('formats whole Rwanda francs', () {
    expect(formatRwf(0), 'RWF 0');
    expect(formatRwf(5000), 'RWF 5,000');
    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(formatMoneyMinor(5000), 'RWF 5,000');
    expect(formatMoneyMinor(-5000), 'RWF -5,000');
  });

  test('RWF keeps its currency label in another device locale', () {
    final formatted = formatRwf(1250000, localeName: 'fr');
    expect(formatted, contains('RWF'));
    expect(formatted, isNot('RWF 1,250,000'));
  });

  test('foreign currencies fail closed', () {
    expect(
      () => formatMoneyMinor(5000, currency: 'EUR'),
      throwsFormatException,
    );
    expect(() => formatCurrencyTotals({'EUR': 5000}), throwsFormatException);
  });
}
