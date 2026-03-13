import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

const _fallbackIntlLocale = 'en';

/// The COOL app is English-only. Always returns 'en'.
String resolveIntlLocale(
  BuildContext context, {
  String fallback = _fallbackIntlLocale,
}) {
  return _fallbackIntlLocale;
}

/// The COOL app is English-only. Always returns 'en'.
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

