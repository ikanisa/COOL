import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/synthetic_jwt.dart';

class _DelayedSmsStatusChannel extends SmsAccessChannel {
  final statusRequested = Completer<void>();
  final statusResult = Completer<SmsAccessStatus>();
  bool _firstOwnerCheck = true;

  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async {
    final acknowledged = !_firstOwnerCheck;
    _firstOwnerCheck = false;
    return acknowledged;
  }

  @override
  Future<SmsAccessStatus> status({String? ownerUserId}) {
    statusRequested.complete();
    return statusResult.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('superseded refresh cannot publish delayed native SMS status', () async {
    final client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/query/public-collections');
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final sms = _DelayedSmsStatusChannel();
    final repository = CollectRepository(
      backend: client,
      smsAccessChannel: sms,
    );
    addTearDown(repository.dispose);

    final superseded = repository.loadInitial();
    await sms.statusRequested.future;
    await repository.loadInitial();
    expect(repository.state.lastError, isNull);
    expect(repository.state.smsSyncNeedsAttention, isFalse);

    sms.statusResult.complete(
      SmsAccessStatus.fromMap({'consent_enabled': true}),
    );
    await superseded;
    expect(repository.state.smsSyncNeedsAttention, isFalse);
  });

  for (final payload in [
    null,
    <String, Object>{'unexpected': true},
  ]) {
    test(
      'member catalogue uses scoped RPC and fails closed on $payload',
      () async {
        final paths = <String>[];
        final client = CollectCloudflareClient(
          'http://127.0.0.1:1',
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path.endsWith('/get_current_member_profile')) {
              return http.Response(
                jsonEncode({
                  'id': '10000000-0000-0000-0000-000000000001',
                  'public_id': '123456',
                  'whatsapp_phone': '250788123456',
                  'country_code': 'RW',
                  'currency_code': 'RWF',
                }),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(request.url.path, '/v1/rpc/list_current_user_collections');
            expect(jsonDecode(request.body), isEmpty);
            return http.Response(
              jsonEncode(payload),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.recoverSession(
          jsonEncode({
            'access_token': syntheticMemberAccessToken(
              '10000000-0000-0000-0000-000000000001',
            ),
            'refresh_token': 'local-test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': '10000000-0000-0000-0000-000000000001',
              'aud': 'authenticated',
              'app_metadata': <String, Object>{},
              'user_metadata': <String, Object>{},
              'created_at': '2026-09-02T00:00:00Z',
            },
          }),
        );
        final repository = CollectRepository(backend: client);
        addTearDown(repository.dispose);
        await repository.loadInitial();
        expect(paths, [
          '/v1/rpc/get_current_member_profile',
          '/v1/rpc/list_current_user_collections',
        ], reason: repository.state.lastError);
        expect(repository.state.hasInitialLoadFailure, isTrue);
        expect(
          repository.state.lastError,
          contains('Group response is unavailable'),
        );
      },
    );
  }
}
