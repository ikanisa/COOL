import 'package:flutter/foundation.dart';

/// Validates required environment variables at app startup.
///
/// Critical vars (Supabase URL, anon key) MUST be provided via
/// `--dart-define`. Invalid or placeholder values are treated as
/// configuration failures and surfaced early at startup.
class EnvConfig {
  EnvConfig._();

  /// Build flavor: 'staging' or 'production'.
  /// Set via --dart-define=FLAVOR=production (defaults to staging).
  static const flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'staging',
  );

  /// Whether running in production flavor.
  static bool get isProduction => flavor == 'production';

  /// Whether running in staging flavor.
  static bool get isStaging => flavor == 'staging';

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const googleMapsAndroidApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_ANDROID_API_KEY',
  );
  static const googleMapsIosApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_IOS_API_KEY',
  );
  static const googleMapsAndroidMapId = String.fromEnvironment(
    'GOOGLE_MAPS_ANDROID_MAP_ID',
  );
  static const googleMapsIosMapId = String.fromEnvironment(
    'GOOGLE_MAPS_IOS_MAP_ID',
  );

  static const deepLinkHost = String.fromEnvironment(
    'COOL_DEEP_LINK_HOST',
    defaultValue: 'cool.app',
  );

  static const enableAndroidMomoSmsAutoread = bool.fromEnvironment(
    'ENABLE_ANDROID_MOMO_SMS_AUTOREAD',
    defaultValue: true,
  );

  static const mobilityGeocodingBaseUrl = String.fromEnvironment(
    'COOL_GEOCODING_BASE_URL',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  static const mobilityGeocodingUserAgent = String.fromEnvironment(
    'COOL_GEOCODING_USER_AGENT',
    defaultValue: 'CoolApp/1.0',
  );

  static const privacyPolicyUrl = String.fromEnvironment(
    'COOL_PRIVACY_POLICY_URL',
    defaultValue: 'https://cool.ikanisa.com/privacy',
  );

  static const termsOfServiceUrl = String.fromEnvironment(
    'COOL_TERMS_OF_SERVICE_URL',
    defaultValue: 'https://cool.ikanisa.com/terms',
  );

  static const accountDeletionUrl = String.fromEnvironment(
    'COOL_ACCOUNT_DELETION_URL',
    defaultValue: 'https://cool.ikanisa.com/account-deletion',
  );

  static const _envDefineHelp =
      'Provide via --dart-define=SUPABASE_URL=https://... and '
      '--dart-define=SUPABASE_ANON_KEY=... or use '
      '--dart-define-from-file=.env.json.';

  static const _placeholderSupabaseUrlValues = <String>{
    'url',
    'your_supabase_project_url',
    'https://your-project.supabase.co',
    'https://your-project-id.supabase.co',
  };

  static const _placeholderSupabaseAnonKeyValues = <String>{
    'anon-key',
    'your_supabase_anon_key',
    'your-anon-key',
  };

  static String? get criticalConfigurationError =>
      describeCriticalConfigurationError(
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
      );

  static String? describeCriticalConfigurationError({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) {
    final normalizedUrl = supabaseUrl.trim();
    if (normalizedUrl.isEmpty) {
      return 'SUPABASE_URL is not set. $_envDefineHelp';
    }

    if (_looksLikePlaceholderValue(
      value: normalizedUrl,
      placeholders: _placeholderSupabaseUrlValues,
    )) {
      return 'SUPABASE_URL must be a real absolute Supabase URL, not '
          '"$normalizedUrl". $_envDefineHelp';
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'SUPABASE_URL must be an absolute URL with scheme and host. '
          'Current value: "$normalizedUrl". $_envDefineHelp';
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'SUPABASE_URL must start with http:// or https://. '
          'Current value: "$normalizedUrl". $_envDefineHelp';
    }

    final normalizedAnonKey = supabaseAnonKey.trim();
    if (normalizedAnonKey.isEmpty) {
      return 'SUPABASE_ANON_KEY is not set. $_envDefineHelp';
    }

    if (_looksLikePlaceholderValue(
      value: normalizedAnonKey,
      placeholders: _placeholderSupabaseAnonKeyValues,
    )) {
      return 'SUPABASE_ANON_KEY is still a placeholder. $_envDefineHelp';
    }

    return null;
  }

  /// Returns a list of warning/error messages for missing or suspect env vars.
  /// Empty list = all good.
  static List<String> validate() {
    final warnings = <String>[];

    final criticalError = criticalConfigurationError;
    if (criticalError != null) {
      warnings.add('${kReleaseMode ? "ERROR" : "WARN"}: $criticalError');
    }

    if (deepLinkHost == 'cool.app') {
      debugPrint(
        'INFO: COOL_DEEP_LINK_HOST is using default "cool.app" — '
        'set for production domain if deploying',
      );
    }
    return warnings;
  }

  /// Whether critical env vars are present.
  static bool get isConfigured => criticalConfigurationError == null;

  /// Logs validation warnings at startup.
  /// In release mode, throws if critical vars (Supabase) are missing.
  static void logWarnings() {
    final warnings = validate();
    for (final w in warnings) {
      debugPrint('[EnvConfig] ⚠️ $w');
    }

    if (kReleaseMode && !isConfigured) {
      throw StateError(
        'FATAL: ${criticalConfigurationError ?? "Missing critical env vars."} '
        'Cannot start in release mode without valid Supabase configuration.',
      );
    }

    if (warnings.isEmpty) {
      debugPrint('[EnvConfig] ✅ All environment variables OK');
    }
  }

  static bool _looksLikePlaceholderValue({
    required String value,
    required Set<String> placeholders,
  }) {
    final normalized = value.trim().toLowerCase();
    return placeholders.contains(normalized) ||
        normalized.contains('your_') ||
        normalized.contains('your-') ||
        normalized.contains('<') ||
        normalized.contains('example');
  }
}
