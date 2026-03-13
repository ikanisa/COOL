import '../../l10n/app_localizations.dart';

const _fallbackLanguageCode = 'en';

/// The COOL app is English-only. This set exists so that callers that
/// previously checked language support continue to compile without changes.
final Set<String> supportedLanguageCodes = AppLocalizations.supportedLocales
    .map((locale) => locale.languageCode.toLowerCase())
    .toSet();

bool isSupportedLanguageCode(String languageCode) {
  return _normalizeLanguageCode(languageCode) == _fallbackLanguageCode;
}

String normalizeSupportedLanguageCode(
  String languageCode, {
  String fallback = _fallbackLanguageCode,
}) {
  // Always English — ignore the input.
  return _fallbackLanguageCode;
}

String _normalizeLanguageCode(String languageCode) {
  final trimmed = languageCode.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return _fallbackLanguageCode;
  }
  return trimmed.split(RegExp('[-_]')).first;
}
