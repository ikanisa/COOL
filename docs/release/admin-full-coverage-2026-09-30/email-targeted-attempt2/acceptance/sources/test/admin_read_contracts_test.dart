import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_operational_health.dart';
import 'package:collect_app/admin/core/admin_read_contracts.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/admin_read_fixture.dart';

const _detailRpcs = [
  'admin_get_user',
  'admin_get_member_record',
  'admin_get_collection',
  'admin_get_notification',
  'admin_get_hybrid_sms_receipt',
  'admin_get_admin_user',
  'admin_get_collect_transaction',
];

http.Response _response(Object? value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  const sqlReceipts = String.fromEnvironment('ADMIN_READ_SQL_RECEIPTS');
  const sqlActor = String.fromEnvironment('ADMIN_READ_SQL_ACTOR');
  test(
    'root-owned actual SQL read receipts satisfy the routed contracts',
    () {
      expect(
        sqlActor,
        matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
      );
      final lines = File(sqlReceipts).readAsLinesSync().where(
        (line) => line.startsWith('ADMIN_READ_RECEIPT_JSON|'),
      );
      final seen = <String>{};
      for (final line in lines) {
        final receipt =
            jsonDecode(line.substring('ADMIN_READ_RECEIPT_JSON|'.length))
                as Map;
        final rpc = receipt['rpc'] as String;
        final value = Map<String, dynamic>.from(receipt['value'] as Map);
        switch (rpc) {
          case 'admin_current_user':
            expect(receipt['id'], isNull);
            expect(parseAdminIdentity(value, actorId: sqlActor), isNotNull);
          case 'admin_overview':
            expect(parseAdminOverview(value), hasLength(4));
          case 'admin_runtime_config':
            parseAdminRuntimeConfig(value);
          case 'admin_system_health':
            expect(receipt['id'], 'system');
            AdminOperationalHealth.parse(value);
          case 'admin_get_queue_sla':
            expect(
              parseAdminQueueSla(value, queueKey: receipt['id'] as String),
              isNotNull,
            );
          case 'admin_get_whatsapp_approval':
            expect(
              adminApprovalReadMatches(receipt['id'] as String, value),
              isTrue,
            );
          default:
            validateAdminDetail(rpc, receipt['id'] as String, value);
        }
        seen.add(rpc);
      }
      expect(
        seen,
        containsAll([
          ..._detailRpcs,
          'admin_current_user',
          'admin_overview',
          'admin_runtime_config',
          'admin_system_health',
          'admin_get_queue_sla',
          'admin_get_whatsapp_approval',
        ]),
      );
    },
    skip: sqlReceipts.isEmpty
        ? 'Root must provide guarded actual SQL receipts.'
        : false,
  );

  test('identity binds actor and preserves immutable capability lists', () {
    final parsed = parseAdminIdentity(
      adminIdentityFixture(),
      actorId: adminReadActor,
    )!;
    expect(parsed.userId, adminReadActor);
    expect(
      () => parsed.permissions.add('admin_users.manage'),
      throwsUnsupportedError,
    );
    expect(parseAdminIdentity(null, actorId: adminReadActor), isNull);
    expect(parseAdminIdentity({}, actorId: adminReadActor), isNull);
  });
  for (final (field, value) in <(String, Object?)>[
    ('user_id', adminReadTarget),
    ('display_name', null),
    ('phone_masked', 1),
    ('roles', ['admin', 1]),
    ('permissions', 'overview.read'),
    ('permissions', ['overview.read', 'overview.read']),
  ]) {
    test('identity rejects malformed or substituted $field=$value', () {
      expect(
        () => parseAdminIdentity({
          ...adminIdentityFixture(),
          field: value,
        }, actorId: adminReadActor),
        throwsFormatException,
      );
    });
  }
  test(
    'overview admits zero and empty without converting unknown data to zero',
    () {
      final metrics = parseAdminOverview({
        'metrics': [
          {'label': 'Active payees', 'value': 0, 'status': 'active'},
        ],
      });
      expect(metrics.single.value, '0');
      expect(parseAdminOverview({'metrics': []}), isEmpty);
    },
  );
  for (final value in [null, '0', -1, 1.0, true, 9007199254740992]) {
    test('overview refuses untrusted count $value', () {
      expect(
        () => parseAdminOverview({
          'metrics': [
            {'label': 'Active payees', 'value': value, 'status': 'active'},
          ],
        }),
        throwsFormatException,
      );
    });
  }
  for (final rpc in _detailRpcs) {
    final id = rpc == 'admin_get_collect_transaction'
        ? 'momo:$adminReadTarget'
        : adminReadTarget;
    test('$rpc accepts current typed source shape and real not-found', () {
      final row = adminDetailFixture(rpc);
      expect(validateAdminDetail(rpc, id, row), row);
      expect(validateAdminDetail(rpc, id, {}), isEmpty);
      expect(
        () => validateAdminDetail(rpc, id, {...row, 'id': adminReadActor}),
        throwsFormatException,
      );
      expect(
        () => validateAdminDetail(rpc, id, {...row}..remove('created_at')),
        throwsFormatException,
      );
      expect(
        () => validateAdminDetail(rpc, id, {
          ...row,
          'unexpected_private_payload': 'hidden',
        }),
        throwsFormatException,
      );
    });
  }
  for (final (rpc, field, value) in <(String, String, Object?)>[
    ('admin_get_user', 'active_groups', '0'),
    ('admin_get_member_record', 'active_groups', -1),
    ('admin_get_collection', 'is_platform_sponsored', 'false'),
    ('admin_get_collection', 'created_at', '2026-02-30T10:00:00Z'),
    ('admin_get_notification', 'retryable_count', -1),
    ('admin_get_hybrid_sms_receipt', 'authorization_current', 'true'),
    ('admin_get_hybrid_sms_receipt', 'template_version', '1'),
    ('admin_get_admin_user', 'user_id', adminReadActor),
    ('admin_get_collect_transaction', 'raw_sms_id', adminReadActor),
    ('admin_get_collect_transaction', 'rail', 'diaspora_account'),
  ]) {
    test('$rpc rejects invalid decision field $field', () {
      final row = adminDetailFixture(rpc);
      final id = row['id'] as String;
      expect(
        () => validateAdminDetail(rpc, id, {...row, field: value}),
        throwsFormatException,
      );
    });
  }
  test(
    'runtime copy stays exact and malformed navigation cannot become a default',
    () {
      final fixture = adminRuntimeFixture();
      final parsed = parseAdminRuntimeConfig(fixture);
      expect(parsed.navigationItems.single.label, 'Groups');
      expect(parsed.queueSpecs.single.statusOptions.first.value, '');
      expect(
        parseAdminRuntimeConfig({
          'navigation_items': [],
          'queue_specs': [],
        }).queueSpecs,
        isEmpty,
      );
      for (final invalid in [
        {...fixture, 'navigation_items': null},
        {...fixture, 'queue_specs': 7},
        {...fixture, 'extra': true},
        {
          ...fixture,
          'navigation_items': [
            {
              ...(fixture['navigation_items'] as List).single as Map,
              'route_path': 'https://example.invalid',
            },
          ],
        },
        {
          ...fixture,
          'navigation_items': [
            {
              ...(fixture['navigation_items'] as List).single as Map,
              'required_permission': null,
            },
          ],
        },
        {
          ...fixture,
          'navigation_items': [
            (fixture['navigation_items'] as List).single,
            (fixture['navigation_items'] as List).single,
          ],
        },
      ]) {
        expect(() => parseAdminRuntimeConfig(invalid), throwsFormatException);
      }
    },
  );

  group('actual Supabase SDK read boundaries', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    late FutureOr<http.Response> Function(http.Request) respond;
    Future<void> login(String session) => client.auth
        .verifyOTP(phone: '+250788974001', token: session, type: OtpType.sms)
        .then((_) {});
    setUp(() async {
      requests = [];
      respond = (_) => _response({});
      client = SupabaseClient(
        'http://127.0.0.1:1',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            final sid = jsonDecode(r.body)['token'];
            return _response({
              'access_token':
                  'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': adminReadActor, 'session_id': sid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
              'refresh_token': 'synthetic-refresh',
              'token_type': 'bearer',
              'user': {
                'id': adminReadActor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': adminReadDate,
              },
            });
          }
          requests.add(r);
          final result = await respond(r);
          return http.Response.bytes(
            result.bodyBytes,
            result.statusCode,
            headers: result.headers,
            request: r,
          );
        }),
      );
      await login('session-a');
    });
    tearDown(() => client.dispose());
    for (final operation in ['identity', 'detail', 'overview', 'runtime']) {
      Future<Object?> call() {
        final repo = AdminRepository(client);
        return switch (operation) {
          'identity' => repo.currentIdentity(),
          'detail' => repo.detail('admin_get_user', adminReadTarget),
          'overview' => repo.overviewMetrics(),
          _ => repo.runtimeConfig(),
        };
      }

      Object valid() => switch (operation) {
        'identity' => adminIdentityFixture(),
        'detail' => adminDetailFixture('admin_get_user'),
        'overview' => {'metrics': []},
        _ => adminRuntimeFixture(),
      };
      test(
        '$operation pins Authorization and suppresses A-B-A late data',
        () async {
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return _response(valid());
          };
          final token = client.auth.currentSession!.accessToken;
          final check = expectLater(
            call(),
            throwsA(isA<AdminSessionChanged>()),
          );
          await started.future;
          await login('session-b');
          await login('session-a');
          release.complete();
          await check;
          expect(requests.single.headers['Authorization'], 'Bearer $token');
        },
      );
      test(
        '$operation retains real permission denial, no empty fallback',
        () async {
          respond = (_) => _response({
            'code': '42501',
            'message': 'synthetic permission denied',
          }, 403);
          await expectLater(call(), throwsA(isA<PostgrestException>()));
          expect(requests, hasLength(1));
        },
      );
    }
    test('malformed detail input is denied before dispatch', () async {
      await expectLater(
        AdminRepository(client).detail('admin_get_user', 'not-a-record'),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    });
    test(
      'missing legacy runtime RPC remains explicit null; permission errors never do',
      () async {
        respond = (_) => _response({
          'code': 'PGRST202',
          'message': 'synthetic RPC absent',
        }, 404);
        expect(await AdminRepository(client).runtimeConfig(), isNull);
      },
    );
  });
}
