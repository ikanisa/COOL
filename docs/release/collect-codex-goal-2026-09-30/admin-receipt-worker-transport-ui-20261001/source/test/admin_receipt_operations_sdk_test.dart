import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

Map<String, dynamic> _observed(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/release/collect-codex-goal-2026-09-30/'
          'receipt-operational-authority-20261001/accepted-sql-attempt7/'
          'observed-$name.json',
        ).readAsStringSync(),
      )
      as Map,
);

Map<String, dynamic> _copy(Map<String, dynamic> row) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(row)) as Map);

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  final configured = _observed('owner-configure');
  final stopped = _observed('owner-stop');
  final recorded = _observed('owner-lookup-recorded');
  final policy = _observed('policy-default');

  final configure = AdminReceiptOperationsIntent.configure(
    requestId: configured['request_id'] as String,
    expectedRevision: (configured['revision'] as int) - 1,
    createdAt: DateTime.parse(configured['recorded_at'] as String),
    expiresAt: DateTime.parse(configured['expires_at'] as String),
    reason: 'Synthetic SDK contract investigation',
    mode: AdminReceiptOperationsMode.shadow,
    emergencyStop: false,
    principalIds: const ['11111111-1111-4111-8111-111111111111'],
    collectionIds: const ['22222222-2222-4222-8222-222222222222'],
    deviceIds: const [],
    caps: AdminReceiptOperationsCaps.parse({
      for (final name in AdminReceiptOperationsCaps.names) name: 1,
    }),
    catchupEnabled: false,
    catchupHours: 24,
  );
  final stop = AdminReceiptOperationsIntent.stop(
    requestId: stopped['request_id'] as String,
    expectedRevision: (stopped['revision'] as int) - 1,
    createdAt: DateTime.parse(stopped['recorded_at'] as String),
    expiresAt: DateTime.parse(stopped['expires_at'] as String),
    reason: 'Synthetic SDK safety stop',
  );

  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(policy);
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(token[0], token[1]));
        }
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'operations-first-session');
    repository = AdminRepository(client);
  });
  tearDown(() async => client.dispose());

  test(
    'actual SQL policy goes through the SDK with the current token',
    () async {
      expect(await repository.receiptOperationsPolicy(), policy);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_receipt_operations_policy_v2',
      );
      expect(
        requests.single.headers['authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );

  test(
    'configure sends only constrained fields and accepts the actual SQL receipt',
    () async {
      respond = (_) async => auth.response(configured);
      expect(
        await repository.configureReceiptOperations(configure),
        configured,
      );
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_configure_receipt_operations_v2',
      );
      expect(jsonDecode(requests.single.body), configure.parameters);
      expect(configure.parameters.containsKey('destination'), isFalse);
      expect(configure.parameters.containsKey('body'), isFalse);
      expect(configure.parameters['p_expires_at'], configured['expires_at']);
    },
  );

  test(
    'stop is a separate deadline-bound RPC with no configuration payload',
    () async {
      respond = (_) async => auth.response(stopped);
      expect(await repository.configureReceiptOperations(stop), stopped);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_stop_receipt_operations_v2',
      );
      expect(jsonDecode(requests.single.body), stop.parameters);
      expect(stop.parameters.keys.toSet(), {
        'p_request_id',
        'p_expected_revision',
        'p_reason',
        'p_expires_at',
      });
    },
  );

  test(
    'current actor looks up only the original UUID and exact SQL evidence',
    () async {
      respond = (_) async => auth.response(recorded);
      expect(
        await repository.receiptOperationsOwnerRequest(configure.requestId),
        recorded,
      );
      expect(jsonDecode(requests.single.body), {
        'p_request_id': configure.requestId,
      });
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_receipt_operations_owner_request_v2',
      );
    },
  );

  test('invalid original request ID causes no HTTP call', () async {
    await expectLater(
      repository.receiptOperationsOwnerRequest('PRIVATE_CANARY'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });

  for (final field in ['request_id', 'revision', 'mode', 'expires_at']) {
    test(
      'misbound configure $field never becomes an acknowledgement',
      () async {
        final wrong = _copy(configured);
        switch (field) {
          case 'request_id':
            wrong[field] = '33333333-3333-4333-8333-333333333333';
          case 'revision':
            wrong[field] = (configured[field] as int) + 1;
          case 'mode':
            wrong[field] = 'Dry-run';
          case 'expires_at':
            wrong[field] = operationsUtc(
              configure.expiresAt.subtract(const Duration(seconds: 1)),
            );
        }
        respond = (_) async => auth.response(wrong);
        await expectLater(
          repository.configureReceiptOperations(configure),
          throwsFormatException,
        );
        expect(requests, hasLength(1));
      },
    );
  }

  test(
    'lookup of a different UUID is rejected even with a valid receipt',
    () async {
      respond = (_) async => auth.response(
        _copy(recorded)
          ..['request_id'] = '33333333-3333-4333-8333-333333333333',
      );
      await expectLater(
        repository.receiptOperationsOwnerRequest(configure.requestId),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );

  for (final operation in ['configure', 'stop', 'lookup', 'policy']) {
    test(
      '$operation HTTP failure is one attempt with no automatic retry',
      () async {
        respond = (_) async => auth.response({
          'message': 'Synthetic unavailable',
          'code': '55000',
        }, 503);
        final future = switch (operation) {
          'configure' => repository.configureReceiptOperations(configure),
          'stop' => repository.configureReceiptOperations(stop),
          'lookup' => repository.receiptOperationsOwnerRequest(
            configure.requestId,
          ),
          _ => repository.receiptOperationsPolicy(),
        };
        await expectLater(future, throwsA(isA<PostgrestException>()));
        expect(requests, hasLength(1));
      },
    );
  }

  test(
    'actual SDK mutation deadline leaves one uncertain original request',
    () async {
      final gate = Completer<http.Response>();
      respond = (_) => gate.future;
      try {
        await expectLater(
          repository.configureReceiptOperations(configure),
          throwsA(isA<TimeoutException>()),
        );
        expect(requests, hasLength(1));
        expect(
          jsonDecode(requests.single.body)['p_request_id'],
          configure.requestId,
        );
        expect(
          jsonDecode(requests.single.body)['p_expires_at'],
          configured['expires_at'],
        );
      } finally {
        // Release the late HTTP call. It cannot turn the timeout into an
        // acknowledgement or authorize a second mutation.
        gate.complete(auth.response(configured));
        await Future<void>.delayed(Duration.zero);
      }
    },
  );

  for (final operation in ['configure', 'lookup', 'policy']) {
    test(
      'departed session suppresses successful $operation response',
      () async {
        final gate = Completer<http.Response>();
        respond = (_) => gate.future;
        final future = switch (operation) {
          'configure' => repository.configureReceiptOperations(configure),
          'lookup' => repository.receiptOperationsOwnerRequest(
            configure.requestId,
          ),
          _ => repository.receiptOperationsPolicy(),
        };
        final checked = expectLater(
          future,
          throwsA(isA<AdminSessionChanged>()),
        );
        while (requests.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        await auth.session(client, 'operations-second-session', nonce: 1);
        gate.complete(
          auth.response(switch (operation) {
            'configure' => configured,
            'lookup' => recorded,
            _ => policy,
          }),
        );
        await checked;
        expect(requests, hasLength(1));
      },
    );
  }
}
