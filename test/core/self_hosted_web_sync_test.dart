import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/cloudflare/realtime_invalidation.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile = <String, String>{
  'admin_origin': 'https://admin.collect.example',
  'environment': 'production',
  'format': 'collect.deployment.v1',
  'google_callback_origin': 'https://admin.collect.example',
  'id': 'collect-selfhost',
  'member_api_origin': 'https://api.collect.example',
  'mode': 'self_hosted',
  'public_origin': 'https://collect.example',
  'supabase_origin': 'https://supabase.collect.example',
};
const _user = '11111111-1111-4111-8111-111111111111';
const _subject = '22222222-2222-4222-8222-222222222222';
const _session = '33333333-3333-4333-8333-333333333333';

CollectSupabaseConfiguration _configuration() {
  final raw = jsonEncode(_profile);
  return CollectSupabaseConfiguration.fromEnvironment(
    AppEnv(
      environmentName: 'production',
      apiUrl: _profile['member_api_origin']!,
      publicUrl: _profile['public_origin']!,
      adminAppUrl: _profile['admin_origin']!,
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: false,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: '',
      authCaptchaSiteKey: '',
      backend: 'supabase',
      supabaseUrl: _profile['supabase_origin']!,
      supabaseApiUrl: _profile['member_api_origin']!,
      supabaseAdminApiUrl: _profile['admin_origin']!,
      supabasePublishableKey: 'sb_publishable_synthetic_key_only',
      deploymentProfile: raw,
      deploymentProfileSha256: sha256.convert(utf8.encode(raw)).toString(),
    ),
  );
}

String _credentials(int revision) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return jsonEncode({
    'access_token':
        '${part({'alg': 'ES256'})}.${part({'sub': _subject, 'session_id': _session, 'iss': '${_profile['supabase_origin']}/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'exp': exp, 'revision': revision})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'user': {'id': _user, 'auth_user_id': _subject},
  });
}

http.Response _reply({int status = 200, String cursor = '0'}) => http.Response(
  status == 200 ? jsonEncode({'events': [], 'cursor': cursor}) : '{}',
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('self-hosted web quiet polls reconcile and ignore stale bearers', (
    tester,
  ) async {
    expect(kIsWeb, isTrue, reason: 'This test must run in the browser runtime.');
    final config = _configuration();
    final requests = <http.Request>[];
    Completer<http.Response>? held;
    var failNext = false;
    final client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (held case final pending?) return pending.future;
        if (failNext) {
          failNext = false;
          return _reply(status: 503);
        }
        return _reply();
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(_credentials(0));
    var now = DateTime.utc(2026, 11, 3);
    var reads = 0;
    final subscription = CollectSyncInvalidationSubscription(
      client: client,
      topic: 'synthetic-web-test',
      areas: collectMobileRealtimeAreas,
      currentTime: () => now,
      debounce: const Duration(milliseconds: 1),
      onInvalidate: () => reads++,
    )..start();
    addTearDown(subscription.dispose);
    await _settle(tester);
    expect(reads, 1, reason: 'The first successful poll reconciles once.');
    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(reads, 1);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(reads, 2, reason: 'A quiet successful poll rechecks authority.');

    final previous = Completer<http.Response>();
    held = previous;
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    await client.auth.recoverSession(
      _credentials(1),
      event: CollectAuthEvent.tokenRefreshed,
    );
    held = null;
    previous.complete(_reply(cursor: '1'));
    await _settle(tester);
    expect(reads, 2, reason: 'A replaced bearer cannot advance the cursor.');
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(requests.last.url.queryParameters['cursor'], '0');
    expect(reads, 3);

    failNext = true;
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(reads, 3);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(reads, 4, reason: 'A successful reconnect reconciles again.');
  });
}
