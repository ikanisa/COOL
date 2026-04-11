import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _wholeMoneyFormat = NumberFormat.decimalPattern('en_US');
final RegExp _nonDigitPattern = RegExp(r'[^0-9]');
final RegExp _digitPattern = RegExp(r'\d');

String formatWholeMoneyAmount(int value) => _wholeMoneyFormat.format(value);

String formatSignedWholeMoneyAmount(int value, {bool includePlus = true}) {
  if (value == 0) {
    return '0';
  }

  final prefix = value > 0 ? (includePlus ? '+' : '') : '-';
  return '$prefix${formatWholeMoneyAmount(value.abs())}';
}

String formatCurrencyAmount(
  int value,
  String currency, {
  bool currencyFirst = false,
  bool signed = false,
  bool includePlus = true,
}) {
  final formatted = signed
      ? formatSignedWholeMoneyAmount(value, includePlus: includePlus)
      : formatWholeMoneyAmount(value);
  return currencyFirst ? '$currency $formatted' : '$formatted $currency';
}

String sanitizeMoneyInput(String raw) => raw.replaceAll(_nonDigitPattern, '');

int? parseWholeMoneyAmount(String raw, {bool allowZero = false}) {
  final digits = sanitizeMoneyInput(raw);
  if (digits.isEmpty) {
    return null;
  }

  final value = int.tryParse(digits);
  if (value == null) {
    return null;
  }
  if (value == 0 && !allowZero) {
    return null;
  }
  if (value < 0) {
    return null;
  }
  return value;
}

class GroupedThousandsInputFormatter extends TextInputFormatter {
  const GroupedThousandsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = sanitizeMoneyInput(newValue.text);
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final parsed = int.tryParse(digits);
    if (parsed == null) {
      return oldValue;
    }

    final formatted = formatWholeMoneyAmount(parsed);
    final digitsAfterCursor = _digitPattern
        .allMatches(newValue.text.substring(newValue.selection.extentOffset))
        .length;

    var newOffset = formatted.length;
    var remainingDigits = digitsAfterCursor;
    while (newOffset > 0 && remainingDigits > 0) {
      newOffset--;
      if (_digitPattern.hasMatch(formatted[newOffset])) {
        remainingDigits--;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }
}
