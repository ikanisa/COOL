import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/shared/utils/collect_share_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public share links preserve a valid configured HTTPS path', () {
    final env = _env(publicUrl: 'https://share.example.com/collect/');

    expect(
      collectPublicLink(env, const ['c', 'kigali-lions']),
      'https://share.example.com/collect/c/kigali-lions',
    );
  });

  test('unsafe or malformed public origins fail closed to Collect', () {
    for (final configured in [
      'javascript:alert(1)',
      'http://collect.ikanisa.com',
      'https://user:pass@collect.ikanisa.com',
      'https://collect.ikanisa.com?redirect=https://example.com',
    ]) {
      expect(
        collectPublicLink(_env(publicUrl: configured), const ['app']),
        'https://collect.ikanisa.com/app',
      );
    }
  });
}

AppEnv _env({required String publicUrl}) => AppEnv(
  supabaseUrl: '',
  supabaseAnonKey: '',
  publicUrl: publicUrl,
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: false,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
);
