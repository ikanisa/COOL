import 'package:collect_app/core/utils/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats EUR minor units with two decimal places', () {
    expect(formatRwf(0), 'EUR 0.00');
    expect(formatRwf(5000), 'EUR 50.00');
    expect(formatRwf(1250000), 'EUR 12,500.00');
  });
}
