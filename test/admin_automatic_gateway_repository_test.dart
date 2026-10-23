import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_automatic_gateway_models.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_automatic_gateway_models_test.dart' as fixture;

void main() {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(
      fixture.automaticFixture('late-contradictory-observation'),
    );
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(parts[0], parts[1]));
        }
        requests.add(request);
        final value = await respond(request);
        return http.Response.bytes(
          value.bodyBytes,
          value.statusCode,
          headers: value.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'automatic-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  test(
    'actual SDK pins the redacted receipt read and authenticated token',
    () async {
      final data = fixture.automaticFixture('late-contradictory-observation');
      await repository.automaticReceiptEvidence(data['receipt_id'] as String);
      expect(
        requests.single.url.path,
        '/v1/rpc/admin_get_gateway_receipt_investigation_v3',
      );
      expect(jsonDecode(requests.single.body), {
        'p_receipt_id': data['receipt_id'],
        'p_limit': 20,
        'p_before_at': null,
        'p_before_request_id': null,
      });
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  test(
    'actual SDK accepts filtered empty continuation without inventing a visible row',
    () async {
      final data = fixture.automaticFixture('filtered-empty-directory');
      respond = (_) async => auth.response(data);
      final result = await repository.automaticDeviceAttempts(
        data['device_id'] as String,
        limit: 1,
      );
      expect(result['rows'], isEmpty);
      expect(result['next_cursor'], isNotNull);
      expect(
        requests.single.url.path,
        '/v1/rpc/admin_list_gateway_device_attempts_v3',
      );
    },
  );
  test('malformed cursor and limit are rejected before HTTP', () async {
    final data = fixture.automaticFixture('directory-first');
    for (final limit in [0, 26]) {
      await expectLater(
        repository.automaticDeviceAttempts(
          data['device_id'] as String,
          limit: limit,
        ),
        throwsRangeError,
      );
    }
    await expectLater(
      repository.automaticDeviceAttempts(
        data['device_id'] as String,
        before: AdminAutomaticDeviceCursor(DateTime.utc(2026), 'invalid'),
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('mixed target response never becomes valid receipt evidence', () async {
    await expectLater(
      repository.automaticReceiptEvidence(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      throwsFormatException,
    );
    expect(requests, hasLength(1));
  });
  test(
    'read authority response cannot add a destination or a send permit',
    () async {
      final data = fixture.automaticFixture('late-contradictory-observation')
        ..['send_authority'] = true;
      respond = (_) async => auth.response(data);
      await expectLater(
        repository.automaticReceiptEvidence(data['receipt_id'] as String),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );
  test(
    'late SDK response from a replaced session cannot publish evidence',
    () async {
      final data = fixture.automaticFixture('late-contradictory-observation');
      final gate = Completer<http.Response>();
      respond = (_) => gate.future;
      final pending = repository.automaticReceiptEvidence(
        data['receipt_id'] as String,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<AdminSessionChanged>()),
      );
      while (requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await auth.session(client, 'automatic-b');
      gate.complete(auth.response(data));
      await assertion;
      expect(requests, hasLength(1));
    },
  );
}
