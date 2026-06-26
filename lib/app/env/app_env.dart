import 'package:flutter_riverpod/flutter_riverpod.dart';

final appEnvProvider = Provider<AppEnv>((ref) => AppEnv.fromEnvironment());

const defaultCollectPublicUrl = 'https://collect.ikanisa.com';
const defaultCollectAdminUrl = 'https://admin.collect.ikanisa.com';

class AppEnv {
  const AppEnv({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.publicUrl,
    required this.adminAppUrl,
    required this.enableSmsReader,
    required this.enableAndroidSmsAccess,
    required this.enableAdminPanel,
    required this.enableAdminDevTools,
    required this.authCaptchaEnabled,
    required this.authCaptchaProvider,
    required this.authCaptchaSiteKey,
    this.appReviewAuthEnabled = false,
    this.appReviewAuthPhone = '',
    this.appReviewAuthOtp = '',
    this.environmentName = 'local',
  });

  factory AppEnv.fromEnvironment() {
    return const AppEnv(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      publicUrl: String.fromEnvironment('APP_PUBLIC_URL'),
      adminAppUrl: String.fromEnvironment('ADMIN_APP_URL'),
      enableSmsReader: bool.fromEnvironment('ENABLE_SMS_READER'),
      enableAndroidSmsAccess: bool.fromEnvironment('ENABLE_ANDROID_SMS_ACCESS'),
      enableAdminPanel: bool.fromEnvironment('ENABLE_ADMIN_PANEL'),
      enableAdminDevTools: bool.fromEnvironment('ENABLE_ADMIN_DEV_TOOLS'),
      authCaptchaEnabled: bool.fromEnvironment('AUTH_CAPTCHA_ENABLED'),
      authCaptchaProvider: String.fromEnvironment('AUTH_CAPTCHA_PROVIDER'),
      authCaptchaSiteKey: String.fromEnvironment('AUTH_CAPTCHA_SITE_KEY'),
      appReviewAuthEnabled: bool.fromEnvironment('APP_REVIEW_AUTH_ENABLED'),
      appReviewAuthPhone: String.fromEnvironment(
        'APP_REVIEW_AUTH_PHONE',
        defaultValue: '',
      ),
      appReviewAuthOtp: String.fromEnvironment(
        'APP_REVIEW_AUTH_OTP',
        defaultValue: '',
      ),
      environmentName: String.fromEnvironment(
        'APP_ENVIRONMENT',
        defaultValue: 'local',
      ),
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String publicUrl;
  final String adminAppUrl;
  final bool enableSmsReader;
  final bool enableAndroidSmsAccess;
  final bool enableAdminPanel;
  final bool enableAdminDevTools;
  final bool authCaptchaEnabled;
  final String authCaptchaProvider;
  final String authCaptchaSiteKey;
  final bool appReviewAuthEnabled;
  final String appReviewAuthPhone;
  final String appReviewAuthOtp;
  final String environmentName;

  bool get hasSupabaseConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
  bool get hasAppReviewAuthConfig =>
      appReviewAuthEnabled &&
      appReviewAuthPhone.trim().isNotEmpty &&
      appReviewAuthOtp.trim().isNotEmpty;
}
