import 'package:flutter/foundation.dart';

/// Validates required environment variables at app startup.
///
/// Critical vars (Supabase URL, anon key) MUST be provided via
/// `--dart-define`. In release builds, missing critical vars are errors.
/// In debug builds, they are warnings (to allow local dev without env).
class EnvConfig {
  EnvConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const appMomoNumber = String.fromEnvironment('COOL_APP_MOMO_NUMBER');

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
    defaultValue: 'https://gen-lang-client-0172279957.web.app/privacy',
  );

  static const termsOfServiceUrl = String.fromEnvironment(
    'COOL_TERMS_OF_SERVICE_URL',
    defaultValue: 'https://gen-lang-client-0172279957.web.app/terms',
  );

  static const accountDeletionUrl = String.fromEnvironment(
    'COOL_ACCOUNT_DELETION_URL',
    defaultValue: 'https://gen-lang-client-0172279957.web.app/account-deletion',
  );

  /// Returns a list of warning/error messages for missing or suspect env vars.
  /// Empty list = all good.
  static List<String> validate() {
    final warnings = <String>[];

    if (supabaseUrl.isEmpty) {
      warnings.add(
        '${kReleaseMode ? "ERROR" : "WARN"}: SUPABASE_URL is not set. '
        'Provide via --dart-define=SUPABASE_URL=https://...',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      warnings.add(
        '${kReleaseMode ? "ERROR" : "WARN"}: SUPABASE_ANON_KEY is not set. '
        'Provide via --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    if (appMomoNumber.isEmpty) {
      warnings.add(
        'WARN: COOL_APP_MOMO_NUMBER is not set — subscription USSD '
        'payments will fail. Set via --dart-define=COOL_APP_MOMO_NUMBER=250...',
      );
    }
    if (deepLinkHost == 'cool.app') {
      warnings.add(
        'INFO: COOL_DEEP_LINK_HOST is using default "cool.app" — '
        'set for production domain if deploying',
      );
    }
    if (googleMapsAndroidMapId.isEmpty && googleMapsIosMapId.isEmpty) {
      warnings.add(
        'INFO: Google Maps map IDs are not set — branded map styling will '
        'stay on the default map until GOOGLE_MAPS_ANDROID_MAP_ID / '
        'GOOGLE_MAPS_IOS_MAP_ID are provided.',
      );
    }
    return warnings;
  }

  static String? googleMapsMapIdForPlatform(TargetPlatform platform) {
    final raw = switch (platform) {
      TargetPlatform.android => googleMapsAndroidMapId,
      TargetPlatform.iOS => googleMapsIosMapId,
      _ => '',
    };
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Whether critical env vars are present.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Logs validation warnings at startup.
  /// In release mode, throws if critical vars (Supabase) are missing.
  static void logWarnings() {
    final warnings = validate();
    for (final w in warnings) {
      debugPrint('[EnvConfig] ⚠️ $w');
    }

    if (kReleaseMode && !isConfigured) {
      throw StateError(
        'FATAL: Missing critical env vars (SUPABASE_URL / '
        'SUPABASE_ANON_KEY). Cannot start in release mode without them. '
        'Provide via --dart-define.',
      );
    }

    if (warnings.isEmpty) {
      debugPrint('[EnvConfig] ✅ All environment variables OK');
    }
  }
}
