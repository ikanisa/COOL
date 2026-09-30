import 'package:collect_app/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
