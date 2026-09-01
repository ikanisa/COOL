import 'package:collect_app/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats whole RWF and diaspora minor units independently', () {
    expect(formatRwf(0), 'RWF 0');
    expect(formatRwf(5000), 'RWF 5,000');
    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(formatMoneyMinor(5000), 'EUR 50.00');
  });

  test('formats money with a locale without losing the ISO currency', () {
    final frenchRwf = formatRwf(1250000, localeName: 'fr');
    final frenchEur = formatMoneyMinor(5000, currency: 'EUR', localeName: 'fr');

    expect(frenchRwf, contains('RWF'));
    expect(frenchRwf, isNot('RWF 1,250,000'));
    expect(frenchEur, contains('EUR'));
  });
}
