import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'synthetic_jwt.dart';

const smsSupabaseProject = 'https://sms-fixture.supabase.co';
const smsSupabasePublishableKey = 'sb_publishable_synthetic_sms_test_key_only';
const smsSupabaseUploadPath =
    '/functions/v1/collect-api/v1/functions/ingest-client-sms';
const smsSupabaseConsentPath =
    '/functions/v1/collect-api/v1/rpc/record_sms_access_consent';

CollectSupabaseConfiguration smsSupabaseConfiguration() =>
    CollectSupabaseConfiguration.fromEnvironment(
      const AppEnv(
        apiUrl: smsSupabaseProject,
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: true,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: 'turnstile',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: smsSupabaseProject,
        supabasePublishableKey: smsSupabasePublishableKey,
      ),
    );

// Deliberately unsigned identity fixtures for MockClient/recoverSession only.
// The authenticated Supabase subject is separate from the Collect queue owner.
Map<String, Object?> smsSupabaseSession({
  required String principal,
  required String authUserId,
  required String sessionId,
}) => {
  'access_token': syntheticJwt(
    {'alg': 'ES256', 'typ': 'JWT'},
    {
      'sub': authUserId,
      'iss': '$smsSupabaseProject/auth/v1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'session_id': sessionId,
      'exp': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    },
  ),
  'refresh_token': 'synthetic-supabase-sms-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': principal,
    'auth_user_id': authUserId,
    'email': 'sms-member@example.invalid',
    'aud': 'authenticated',
    'app_metadata': <String, Object>{},
    'user_metadata': <String, Object>{},
    'created_at': '2026-10-19T00:00:00Z',
  },
};

void expectSupabaseSmsRequest(http.Request request) {
  expect(request.method, 'POST');
  expect(request.url.origin, smsSupabaseProject);
  expect(
    request.url.path,
    anyOf(smsSupabaseUploadPath, smsSupabaseConsentPath),
  );
  expect(request.url.hasQuery, isFalse);
  expect(request.headers['apikey'], smsSupabasePublishableKey);
  expect(request.headers['authorization'], startsWith('Bearer '));
}
