import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_reconciliation_step_up.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

class _ReadCase {
  const _ReadCase(
    this.name,
    this.endpoint,
    this.params,
    this.receipt,
    this.read,
  );
  final String name, endpoint;
  final Map<String, dynamic> params;
  final Object receipt;
  final Future<Object?> Function(AdminRepository) read;
}

void main() {
  final health = Map<String, dynamic>.from(
    (jsonDecode(
              File(
                'test/fixtures/admin_operational_health148.json',
              ).readAsStringSync(),
            )
            as Map)['receipt']
        as Map,
  );
  final cases = <_ReadCase>[
    _ReadCase(
      'admin_current_user',
      'admin_current_user',
      {},
      adminIdentityFixture(sdk.actor),
      (r) => r.currentIdentity(),
    ),
    _ReadCase('admin_overview', 'admin_overview', {}, {
      'metrics': [],
    }, (r) => r.overviewMetrics()),
    _ReadCase(
      'admin_runtime_config',
      'admin_runtime_config',
      {},
      adminRuntimeFixture(),
      (r) => r.runtimeConfig(),
    ),
    for (final rpc in [
      'admin_get_collection',
      'admin_get_user',
      'admin_get_member_record',
      'admin_get_collect_transaction',
      'admin_get_hybrid_sms_receipt',
      'admin_get_notification',
      'admin_get_admin_user',
    ])
      _ReadCase(
        rpc,
        rpc,
        {
          'p_id': rpc == 'admin_get_collect_transaction'
              ? 'momo:${sdk.target}'
              : sdk.target,
        },
        adminDetailFixture(rpc, sdk.target),
        (r) => r.detail(
          rpc,
          rpc == 'admin_get_collect_transaction'
              ? 'momo:${sdk.target}'
              : sdk.target,
        ),
      ),
    _ReadCase(
      'admin_system_health',
      'admin_system_health',
      {'p_id': 'system'},
      health,
      (r) => r.detail('admin_system_health', 'system'),
    ),
    for (final rpc in [
      'admin_list_collections',
      'admin_list_non_member_users',
      'admin_list_members',
      'admin_list_collect_payees',
      'admin_list_collect_transactions',
      'admin_list_collect_reconciliations',
      'admin_list_collect_ledgers',
      'admin_list_hybrid_sms_receipts',
      'admin_list_notifications',
      'admin_list_audit_logs',
      'admin_list_settings',
      'admin_list_feature_flags',
      'admin_list_admin_users',
    ])
      _ReadCase(
        rpc,
        adminRpcUsesCountryScope(rpc) ? 'admin_list_country_scoped' : rpc,
        {
          if (adminRpcUsesCountryScope(rpc)) 'p_rpc_name': rpc,
          if (adminRpcUsesCountryScope(rpc)) 'p_country': 'RW',
          'p_search': 'synthetic-filter',
          'p_status': 'active',
          'p_limit': 25,
          'p_offset': 0,
          'p_sort': 'created_at_desc',
        },
        {'rows': [], 'total': 0},
        (r) => r.list(
          rpc,
          countryCode: 'RW',
          search: ' synthetic-filter ',
          status: ' active ',
          limit: 25,
          offset: 0,
          sortBy: 'created_at_desc',
        ),
      ),
    _ReadCase(
      'admin_get_queue_sla',
      'admin_get_queue_sla',
      {'p_queue_key': 'admin_list_collect_reconciliations'},
      {
        'queue_key': 'admin_list_collect_reconciliations',
        'target': 'Next business day',
        'owner': 'Synthetic operator',
        'escalation': 'Escalate unresolved variance',
        'updated_at': adminReadDate,
      },
      (r) => r.queueSla('admin_list_collect_reconciliations'),
    ),
    _ReadCase(
      'admin_get_whatsapp_approval',
      'admin_get_whatsapp_approval',
      {'p_user_id': sdk.target},
      {
        'user_id': sdk.target,
        'phone_masked': null,
        'approved_at': null,
        'expires_at': null,
        'status': 'not_approved',
        'approved': false,
        'role_granted': false,
        'admin_access': false,
        'access_status': 'revoked',
      },
      (r) => r.action('admin_get_whatsapp_approval', {'p_user_id': sdk.target}),
    ),
    _ReadCase(
      'collect-notification-operator.health',
      'collect-notification-operator',
      {'action': 'health'},
      {
        'ok': true,
        'action': 'health',
        'result': {
          'enabled': false,
          'queued': 0,
          'awaiting_confirmation': 0,
          'send_started': 0,
          'uncertain': 0,
          'suppressed': 0,
          'active_workers': 0,
          'oldest_queued_at': null,
          'observed_at': adminReadDate,
        },
      },
      (r) => r.smsQueueHealth(),
    ),
    _ReadCase(
      'list_payment_reconciliations_v2',
      'list_payment_reconciliations_v2',
      {'p_payment_id': sdk.target, 'p_limit': 25, 'p_offset': 0},
      {'rows': [], 'total': 0},
      (r) => r.paymentReconciliationReviews(sdk.target),
    ),
    _ReadCase(
      'get_payment_reconciliation_v2',
      'get_payment_reconciliation_v2',
      {'p_review_id': sdk.actor},
      {
        'id': sdk.actor,
        'payment_id': sdk.target,
        'audit': [],
        'journals': [],
        'receiver_routes': [],
      },
      (r) => r.paymentReconciliationDetail(sdk.actor, paymentId: sdk.target),
    ),
  ];
  late SupabaseClient client;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => sdk.response({});
    client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          final receipt = sdk.authReceipt(token[0], token[1]);
          if (token[0] == 'expired-declared-read') {
            final parts = (receipt['access_token'] as String).split('.');
            final claims =
                jsonDecode(
                      utf8.decode(
                        base64Url.decode(base64Url.normalize(parts[1])),
                      ),
                    )
                    as Map<String, dynamic>;
            claims['exp'] = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
            receipt['access_token'] =
                '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
          }
          return sdk.response(receipt);
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
    await sdk.session(client, 'declared-read-a');
  });
  tearDown(() => client.dispose());
  for (final value in cases) {
    test('${value.name} expired JWT dispatches no request', () async {
      await sdk.session(client, 'expired-declared-read');
      await expectLater(
        value.read(AdminRepository(client)),
        throwsA(
          anyOf(
            isA<AdminSessionChanged>(),
            isA<AdminReconciliationStepUpException>(),
          ),
        ),
      );
      expect(requests, isEmpty);
    });
    test(
      '${value.name} sends the declared request and captured Bearer',
      () async {
        respond = (_) async => sdk.response(value.receipt);
        final token = client.auth.currentSession!.accessToken;
        expect(await value.read(AdminRepository(client)), isNotNull);
        expect(requests, hasLength(1));
        expect(requests.single.url.path.split('/').last, value.endpoint);
        expect(requests.single.headers['Authorization'], 'Bearer $token');
        expect(
          jsonDecode(requests.single.body),
          value.params.isEmpty ? isNull : value.params,
        );
      },
    );
    test(
      '${value.name} preserves genuine permission denial with no retry or fallback',
      () async {
        respond = (_) async => sdk.response({
          'code': '42501',
          'message': 'Synthetic permission denied',
        }, 403);
        await expectLater(
          value.read(AdminRepository(client)),
          throwsA(anyOf(isA<PostgrestException>(), isA<FunctionException>())),
        );
        expect(requests, hasLength(1));
      },
    );
    for (final back in [false, true]) {
      test('${value.name} rejects an old late response; A-B-A=$back', () async {
        final began = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          began.complete();
          await release.future;
          return sdk.response(value.receipt);
        };
        final changed = value.name.contains('payment_reconciliation')
            ? isA<AdminReconciliationStepUpException>()
            : isA<AdminSessionChanged>();
        final check = expectLater(
          value.read(AdminRepository(client)),
          throwsA(changed),
        );
        await began.future;
        await sdk.session(client, 'declared-read-b');
        if (back) await sdk.session(client, 'declared-read-a');
        release.complete();
        await check;
        expect(requests, hasLength(1));
      });
    }
  }
}
