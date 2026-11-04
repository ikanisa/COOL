import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/core/payments/rwf_submission_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts exact positive whole amounts and correct grouping', () {
    for (final entry in <(String, int)>[
      ('1', 1),
      ('0001', 1),
      ('1234', 1234),
      ('1,234', 1234),
      ('001,234', 1234),
      ('9,007,199,254,740,991', maxExactJsonInteger),
    ]) {
      expect(
        parseRwfSubmissionAmount(entry.$1, isComposing: false),
        entry.$2,
        reason: entry.$1,
      );
    }
  });

  test('rejects composing, invalid and unsafe amounts', () {
    expect(parseRwfSubmissionAmount('123', isComposing: true), isNull);
    for (final text in [
      '',
      '0',
      '000',
      '1.5',
      '-20',
      '+1',
      '١2',
      '１２',
      '1 234',
      '1\n',
      ',123',
      '123,',
      '1,,234',
      '12,34',
      '1234,567',
      '9,007,199,254,740,992',
      '9007199254740992',
    ]) {
      expect(
        parseRwfSubmissionAmount(text, isComposing: false),
        isNull,
        reason: text,
      );
    }
  });
}
