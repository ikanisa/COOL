import 'package:collect_app/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats whole RWF and diaspora minor units independently', () {
    expect(formatRwf(0), 'RWF 0');
    expect(formatRwf(5000), 'RWF 5,000');
    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(formatMoneyMinor(5000), 'EUR 50.00');
  });
}
