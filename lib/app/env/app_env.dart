import 'package:flutter_riverpod/flutter_riverpod.dart';

final appEnvProvider = Provider<AppEnv>((ref) => AppEnv.fromEnvironment());

const defaultCollectPublicUrl = 'https://collect.ikanisa.com';
const defaultCollectAdminUrl = 'https://admin.collect.ikanisa.com';

class AppEnv {
  const AppEnv({
    required this.apiUrl,
    required this.publicUrl,
    required this.adminAppUrl,
    required this.enableSmsReader,
    required this.enableAndroidSmsAccess,
    required this.enableAdminPanel,
    required this.enableAdminDevTools,
    required this.authCaptchaEnabled,
    required this.authCaptchaProvider,
    required this.authCaptchaSiteKey,
    this.environmentName = 'local',
    this.backend = 'supabase',
    this.supabaseUrl = '',
    this.supabaseApiUrl = '',
    this.supabaseAdminApiUrl = '',
    this.supabasePublishableKey = '',
  });

  factory AppEnv.fromEnvironment() {
    return const AppEnv(
      apiUrl: String.fromEnvironment('COLLECT_API_URL'),
      publicUrl: String.fromEnvironment('APP_PUBLIC_URL'),
      adminAppUrl: String.fromEnvironment('ADMIN_APP_URL'),
      enableSmsReader: bool.fromEnvironment('ENABLE_SMS_READER'),
      enableAndroidSmsAccess: bool.fromEnvironment(
        'ENABLE_ANDROID_SMS_ACCESS',
        defaultValue: true,
      ),
      enableAdminPanel: bool.fromEnvironment('ENABLE_ADMIN_PANEL'),
      enableAdminDevTools: bool.fromEnvironment('ENABLE_ADMIN_DEV_TOOLS'),
      authCaptchaEnabled: bool.fromEnvironment('AUTH_CAPTCHA_ENABLED'),
      authCaptchaProvider: String.fromEnvironment('AUTH_CAPTCHA_PROVIDER'),
      authCaptchaSiteKey: String.fromEnvironment('AUTH_CAPTCHA_SITE_KEY'),
      environmentName: String.fromEnvironment(
        'APP_ENVIRONMENT',
        defaultValue: 'local',
      ),
      backend: String.fromEnvironment(
        'COLLECT_BACKEND',
        defaultValue: 'supabase',
      ),
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabaseApiUrl: String.fromEnvironment('SUPABASE_API_URL'),
      supabaseAdminApiUrl: String.fromEnvironment('SUPABASE_ADMIN_API_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
    );
  }

  final String apiUrl;
  final String publicUrl;
  final String adminAppUrl;
  final bool enableSmsReader;
  final bool enableAndroidSmsAccess;
  final bool enableAdminPanel;
  final bool enableAdminDevTools;
  final bool authCaptchaEnabled;
  final String authCaptchaProvider;
  final String authCaptchaSiteKey;
  final String environmentName;
  final String backend;
  final String supabaseUrl;
  final String supabaseApiUrl;
  final String supabaseAdminApiUrl;
  final String supabasePublishableKey;

  bool get usesSupabase => backend == 'supabase';
  bool get hasBackendConfig =>
      usesSupabase || backend != 'cloudflare' || apiUrl.trim().isNotEmpty;
}
