import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/features/home/app_share_service.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed-in app share uses a recipient-safe universal invite link', () {
    final env = _env(publicUrl: 'https://collect.ikanisa.com');
    const profile = CollectProfile(
      id: 'profile-id',
      publicId: '038491',
      whatsappPhone: '+250788123456',
    );

    expect(
      collectAppInviteLinkFor(env, profile),
      'https://collect.ikanisa.com/invite/038491',
    );
    expect(
      collectAppShareMessageFor(env, profile),
      contains('Open the app or get it for your phone'),
    );
    expect(
      collectAppShareMessageFor(env, profile),
      endsWith('https://collect.ikanisa.com/invite/038491'),
    );
  });

  test('anonymous app share fails closed to the public app route', () {
    final env = _env(publicUrl: 'javascript:alert(1)');

    expect(
      collectAppInviteLinkFor(env, null),
      'https://collect.ikanisa.com/app',
    );
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
