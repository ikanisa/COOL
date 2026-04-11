import 'package:cool_app/core/utils/money_formatters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money formatters', () {
    test('formats whole amounts with thousands separators', () {
      expect(formatWholeMoneyAmount(12345), '12,345');
      expect(formatWholeMoneyAmount(987654321), '987,654,321');
    });

    test('formats signed amounts with leading sign', () {
      expect(formatSignedWholeMoneyAmount(12345), '+12,345');
      expect(formatSignedWholeMoneyAmount(-12345), '-12,345');
      expect(formatSignedWholeMoneyAmount(0), '0');
    });

    test('parses grouped input into integers', () {
      expect(parseWholeMoneyAmount('12,345'), 12345);
      expect(parseWholeMoneyAmount('RWF 98,765'), 98765);
      expect(parseWholeMoneyAmount('0'), isNull);
      expect(parseWholeMoneyAmount('0', allowZero: true), 0);
    });

    test('input formatter inserts grouping separators', () {
      const formatter = GroupedThousandsInputFormatter();
      final value = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(
          text: '12345',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(value.text, '12,345');
      expect(value.selection.baseOffset, 6);
    });
  });
}
