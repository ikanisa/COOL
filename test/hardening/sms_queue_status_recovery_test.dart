import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/collect_repository_fixture.dart';
import '../support/supabase_sms_fixture.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _authOwner = 'a1111111-1111-4111-8111-111111111111';
const _ownerSession = 'b1111111-1111-4111-8111-111111111111';

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

  for (final priorDeviceConsent in [false, true]) {
    test(
      priorDeviceConsent
          ? 'observed OS revocation withdraws prior device SMS consent'
          : 'passive status without device opt-in does not withdraw SMS consent',
      () async {
        final requests = <http.Request>[];
        final config = smsSupabaseConfiguration();
        final client = CollectCloudflareClient(
          config.api.origin,
          supabaseConfiguration: config,
          httpClient: MockClient((request) async {
            expectSupabaseSmsRequest(request);
            requests.add(request);
            return http.Response(
              'null',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.recoverSession(
          jsonEncode(
            smsSupabaseSession(
              principal: _owner,
              authUserId: _authOwner,
              sessionId: _ownerSession,
            ),
          ),
        );
        final channel = _StatusChannel(
          SmsAccessStatus(
            supported: true,
            declared: true,
            enabled: false,
            consentEnabled: priorDeviceConsent,
            granted: false,
            requestedBefore: priorDeviceConsent,
            shouldShowRationale: false,
            permanentlyDenied: priorDeviceConsent,
            queueOverflowed: false,
          ),
        );
        final repository = FixtureCollectRepository(
          backend: client,
          smsAccessChannel: channel,
          profileOverride: const CollectProfile(
            id: _owner,
            publicId: '038491',
            whatsappPhone: '',
            countryCode: 'DE',
            currencyCode: 'EUR',
          ),
        );
        addTearDown(repository.dispose);
        await repository.refreshSmsAccessStatus();
        expect(channel.disableCalls, priorDeviceConsent ? 1 : 0);
        expect(requests.length, priorDeviceConsent ? 1 : 0);
        if (priorDeviceConsent) {
          expect(requests.single.url.path, smsSupabaseConsentPath);
          expect(
            requests.single.headers['authorization'],
            'Bearer ${client.auth.currentSession!.accessToken}',
          );
          expect(client.auth.currentUser?.id, _owner);
          expect(client.auth.currentSession?.claims['sub'], _authOwner);
          expect((jsonDecode(requests.single.body) as Map)['enabled'], false);
        }
      },
    );
  }

  for (final status in [
    _status(unavailable: true),
    _status(overflowed: true),
  ]) {
    test(
      'status refresh preserves pending evidence when queue needs review',
      () async {
        final requests = <String>[];
        final config = smsSupabaseConfiguration();
        final client = CollectCloudflareClient(
          config.api.origin,
          supabaseConfiguration: config,
          httpClient: MockClient((request) async {
            expectSupabaseSmsRequest(request);
            requests.add(request.url.path);
            return http.Response(
              'null',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.recoverSession(
          jsonEncode(
            smsSupabaseSession(
              principal: _owner,
              authUserId: _authOwner,
              sessionId: _ownerSession,
            ),
          ),
        );
        final channel = _StatusChannel(status);
        final repository = FixtureCollectRepository(
          backend: client,
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
