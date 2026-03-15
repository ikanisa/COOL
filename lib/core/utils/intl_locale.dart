import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

const _fallbackIntlLocale = 'en';

/// COOL is fixed to the Rwanda market and English-only.
///
/// Formatting must not follow the device locale because that would create
/// mixed-language and mixed-format behavior in a product that intentionally
/// enforces a single market and language.
String resolveIntlLocale(
  BuildContext context, {
  String fallback = _fallbackIntlLocale,
}) {
  return _fallbackIntlLocale;
}

/// COOL is English-only. Locale input is intentionally ignored.
String resolveIntlLocaleTag(
  Locale? locale, {
  String fallback = _fallbackIntlLocale,
}) {
  return _fallbackIntlLocale;
}

NumberFormat decimalMoneyFormatForLocale(
  BuildContext context, {
  String fallback = _fallbackIntlLocale,
}) {
  final locale = resolveIntlLocale(context, fallback: fallback);
  return NumberFormat.decimalPattern(locale);
}

DateFormat safeDateFormat(
  String pattern, {
  Locale? locale,
  String fallback = _fallbackIntlLocale,
}) {
  final localeTag = resolveIntlLocaleTag(locale, fallback: fallback);
  try {
    return DateFormat(pattern, localeTag);
  } catch (_) {
    return DateFormat(pattern);
  }
}
