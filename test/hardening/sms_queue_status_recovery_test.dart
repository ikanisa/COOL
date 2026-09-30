import 'dart:convert';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/collect_repository_fixture.dart';

const _owner = '11111111-1111-4111-8111-111111111111';

class _StatusChannel extends SmsAccessChannel {
  _StatusChannel(this.current);

  final SmsAccessStatus current;
  int disableCalls = 0;

  @override
  Future<SmsAccessStatus> status() async => current;

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    if (!enabled) disableCalls++;
    return true;
  }
}

SmsAccessStatus _status({bool unavailable = false, bool overflowed = false}) =>
    SmsAccessStatus(
      supported: true,
      declared: true,
      enabled: false,
      granted: true,
      requestedBefore: true,
      shouldShowRationale: false,
      permanentlyDenied: false,
      queueOverflowed: overflowed,
      queueUnavailable: unavailable,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final status in [
    _status(unavailable: true),
    _status(overflowed: true),
  ]) {
    test(
      'status refresh preserves pending evidence when queue needs review',
      () async {
        final requests = <String>[];
        final client = SupabaseClient(
          'http://127.0.0.1:1',
          'local-test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request.url.path);
            return http.Response(
              'null',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'local-test-access',
            'refresh_token': 'local-test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': _owner,
              'aud': 'authenticated',
              'app_metadata': <String, Object>{},
              'user_metadata': <String, Object>{},
              'created_at': '2026-09-28T00:00:00Z',
            },
          }),
        );
        final channel = _StatusChannel(status);
        final repository = FixtureCollectRepository(
          supabase: client,
          smsAccessChannel: channel,
          profileOverride: const CollectProfile(
            id: _owner,
            publicId: '038491',
            whatsappPhone: '+250788123456',
            countryCode: 'RW',
            currencyCode: 'RWF',
            momoProvider: 'mtn_momo',
            momoNumber: '0788123456',
          ),
        );
        addTearDown(repository.dispose);

        await repository.refreshSmsAccessStatus();

        expect(channel.disableCalls, 0);
        expect(requests, isEmpty);
        expect(repository.state.smsSyncNeedsAttention, isTrue);
        expect(repository.state.smsQueueOverflowed, status.queueOverflowed);
      },
    );
  }
}
