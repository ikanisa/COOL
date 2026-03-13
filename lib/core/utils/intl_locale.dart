import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

const _fallbackIntlLocale = 'en';

String resolveIntlLocale(
  BuildContext context, {
  String fallback = _fallbackIntlLocale,
}) {
  return resolveIntlLocaleTag(
    Localizations.maybeLocaleOf(context),
    fallback: fallback,
  );
}

String resolveIntlLocaleTag(
  Locale? locale, {
  String fallback = _fallbackIntlLocale,
}) {
  final candidates = <String>[
    if (locale != null) locale.toLanguageTag(),
    if (locale != null &&
        locale.languageCode.isNotEmpty &&
        (locale.countryCode?.isNotEmpty ?? false))
      '${locale.languageCode}_${locale.countryCode}',
    if (locale != null && locale.languageCode.isNotEmpty) locale.languageCode,
    fallback,
  ];

  for (final candidate in candidates) {
    if (_supportsIntlNumberFormatting(candidate)) {
      return candidate;
    }
  }

  return fallback;
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

bool _supportsIntlNumberFormatting(String localeTag) {
  try {
    NumberFormat.decimalPattern(localeTag);
    return true;
  } catch (_) {
    return false;
  }
}
