import '../../l10n/app_localizations.dart';

const _fallbackLanguageCode = 'en';

final Set<String> supportedLanguageCodes = AppLocalizations.supportedLocales
    .map((locale) => locale.languageCode.toLowerCase())
    .toSet();

bool isSupportedLanguageCode(String languageCode) {
  final normalized = _normalizeLanguageCode(languageCode);
  return supportedLanguageCodes.contains(normalized);
}

String normalizeSupportedLanguageCode(
  String languageCode, {
  String fallback = _fallbackLanguageCode,
}) {
  final normalized = _normalizeLanguageCode(languageCode);
  if (supportedLanguageCodes.contains(normalized)) {
    return normalized;
  }
  return fallback;
}

String _normalizeLanguageCode(String languageCode) {
  final trimmed = languageCode.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return _fallbackLanguageCode;
  }
  return trimmed.split(RegExp('[-_]')).first;
}
