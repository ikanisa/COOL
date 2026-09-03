import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = RwfAmountInputFormatter();
  TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );

  test('groups digits as the user types', () {
    var current = value('');
    for (final digit in '1234567'.split('')) {
      current = formatter.formatEditUpdate(
        current,
        value('${current.text}$digit'),
      );
    }
    expect(current.text, '1,234,567');
    expect(current.selection.extentOffset, 9);
  });

  test('accepts grouped paste and normalizes leading zeroes', () {
    expect(formatter.formatEditUpdate(value(''), value('1,234')).text, '1,234');
    final result = formatter.formatEditUpdate(value(''), value('0001234'));
    expect(result.text, '1,234');
    expect(result.selection.extentOffset, 5);
    expect(formatter.formatEditUpdate(value(''), value('000')).text, '0');
  });

  test(
    'rejects fractions signs and letters instead of changing their value',
    () {
      final old = value('1,234');
      for (final invalid in ['-1234', '12.34', '1234a', '+1234']) {
        expect(formatter.formatEditUpdate(old, value(invalid)), old);
      }
    },
  );

  test('retains cursor position on middle insertion', () {
    final result = formatter.formatEditUpdate(
      value('1,234', 2),
      value('1,9234', 3),
    );
    expect(result.text, '19,234');
    expect(result.selection.extentOffset, 2);
  });

  test('backspace across comma removes the preceding digit', () {
    final result = formatter.formatEditUpdate(
      value('1,234', 2),
      value('1234', 1),
    );
    expect(result.text, '234');
    expect(result.selection.extentOffset, 0);
  });

  test('forward delete across comma removes the following digit', () {
    final result = formatter.formatEditUpdate(
      value('1,234', 1),
      value('1234', 1),
    );
    expect(result.text, '134');
    expect(result.selection.extentOffset, 1);
  });

  test('preserves a reverse selection by digit position', () {
    final result = formatter.formatEditUpdate(
      value(''),
      const TextEditingValue(
        text: '1234567',
        selection: TextSelection(baseOffset: 6, extentOffset: 2),
      ),
    );
    expect(result.text, '1,234,567');
    expect(
      result.selection,
      const TextSelection(baseOffset: 8, extentOffset: 3),
    );
  });

  test('retains a caret immediately after an existing grouping separator', () {
    final input = value('12,345', 3);
    expect(formatter.formatEditUpdate(input, input), input);
  });

  test('clearing and replacing selected text remain editable', () {
    expect(formatter.formatEditUpdate(value('1,234'), value('')).text, '');
    const old = TextEditingValue(
      text: '12,345',
      selection: TextSelection(baseOffset: 0, extentOffset: 3),
    );
    final result = formatter.formatEditUpdate(old, value('9345', 1));
    expect(result.text, '9,345');
    expect(result.selection.extentOffset, 1);
  });

  test('does not round long numeric input', () {
    expect(
      formatter.formatEditUpdate(value(''), value('9007199254740993')).text,
      '9,007,199,254,740,993',
    );
  });

  test('does not modify active IME composition', () {
    const input = TextEditingValue(
      text: '1234',
      composing: TextRange(start: 0, end: 4),
    );
    expect(formatter.formatEditUpdate(value(''), input), input);
  });
}
