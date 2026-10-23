import 'package:collect_app/app/env/app_env.dart';

/// Explicit selection for synthetic tests of the retained legacy protocol.
/// Production entrypoints keep the Supabase default and configuration checks.
const legacyBackendFixtureEnvironment = AppEnv(
  apiUrl: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: true,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  backend: 'cloudflare',
);
