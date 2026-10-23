// Actual canonical parent -> host/providers -> repository -> pinned Auth/HTTP
// adapters over retained producer execution bytes. HTTP/Auth are synthetic.
// Legacy approval/root IDs and page size are explicitly adapted to join the
// independent producer fixtures; this is caller proof, not a new SQL lifecycle.
import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_view.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/successor_fixture.dart';
import 'support/recorded_auth_fixture.dart';
import 'dart:io';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';

const actor = '99440000-0000-4000-8000-000000000001';
const summaryRpc = 'admin_get_receipt_successor_execution_v5';
const pageRpc = 'admin_list_receipt_successor_observations_v5';

class DeadlineMountedHarness {
  final execution = DeadlineExecutionFixture();
  final legacy = SuccessorFixture();
  final requests = <http.Request>[];
  late CollectCloudflareClient client;
  late ProviderContainer container;
  late AdminReceiptSuccessorController controller;
  bool denyParentPage = false, timeoutParentPage = false;
  bool owner = true;
  bool deadlineDenied = false, deadlineTimeout = false;
  Map<String, dynamic>? aggregateSample, primaryDeadlinePage;
  bool aggregateDenied = false, aggregateTimeout = false;
  Completer<void>? aggregateEntered, aggregateRelease;
  Completer<void>? deadlineEntered, deadlineRelease;
  Completer<void>? summaryEntered, summaryRelease;

  Map<String, dynamic> history({bool more = false}) {
    final result = clone(
      Map<String, dynamic>.from(observed('lineage_pages')['first'] as Map),
    );
    final template = clone(
      Map<String, dynamic>.from((result['items'] as List).first as Map),
    );
    result['outbox_id'] = legacy.outbox;
    result['items'] = List.generate(more ? 1 : 20, (i) {
      final item = clone(template);
      item['sequence'] = more ? 21 : i + 1;
      item['approval_id'] =
          '99440000-0000-4000-8000-${(81000 + (more ? 21 : i)).toString().padLeft(12, '0')}';
      item['outbox_id'] = legacy.outbox;
      (item['preview'] as Map)['root_outbox_id'] = legacy.outbox;
      (item['preview'] as Map)['source_snapshot_id'] = legacy.source;
      return item;
    });
    result['has_more'] = !more;
    result['next_after'] = more ? null : 20;
    return result;
  }

  Future<void> start() async {
    // The retained page was observed 60ms after its summary. Use one clock
    // after both producer samples and inside both original validity windows.
    execution.now = execution.original.checkedAt.add(
      const Duration(seconds: 1),
    );
    legacy.outboxOverride = execution.root;
    legacy.now = execution.now;
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        http.Response reply(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        if (request.url.path == '/v1/auth/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': actor, 'session_id': 'mounted-session', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'email': 'operator@example.invalid',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-10-02T00:00:00Z',
            },
          });
        }
        if (request.url.path == '/v1/auth/logout') return reply({});
        requests.add(request);
        final rpc = request.url.path.split('/').last;
        if (rpc == 'admin_current_user') {
          return reply({
            'user_id': actor,
            'display_name': 'Synthetic mounted reviewer',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': [
              'payments.read',
              'notifications.read',
              'system_health.read',
            ],
          });
        }
        if (rpc == 'admin_list_receipt_callback_deadlines_v1') {
          deadlineEntered?.complete();
          await deadlineRelease?.future;
          if (deadlineDenied) {
            return reply({'code': '42501', 'message': 'Synthetic denial'}, 403);
          }
          if (deadlineTimeout) throw TimeoutException('Synthetic timeout');
          final params = jsonDecode(request.body) as Map;
          return reply(
            params['p_protocol_family'] == 'primary_v2' &&
                    primaryDeadlinePage != null
                ? primaryDeadlinePage!
                : sqlFixture(
                    params['p_protocol_family'] == 'receipt_successor'
                        ? 'fresh-successor-list'
                        : 'fresh-primary-list',
                  ),
          );
        }
        if (rpc == 'admin_get_receipt_aggregate_sample_v2') {
          if (aggregateEntered?.isCompleted == false) {
            aggregateEntered!.complete();
          }
          await aggregateRelease?.future;
          if (aggregateDenied) {
            return reply({'code': '42501', 'message': 'Synthetic denial'}, 403);
          }
          if (aggregateTimeout) {
            throw TimeoutException('Synthetic aggregate timeout');
          }
          final params = jsonDecode(request.body) as Map;
          return reply(
            aggregateSample ??
                {
                  'contract_version': 2,
                  'request_id': params['p_request_id'],
                  'status': 'unavailable',
                  'result': null,
                  'financial_action': false,
                  'send_action': false,
                },
          );
        }
        if (rpc == 'admin_get_receipt_operational_telemetry_v1') {
          return reply({
            'code': '503',
            'message': 'Synthetic unavailable aggregate',
          }, 503);
        }
        if (rpc == summaryRpc) {
          summaryEntered?.complete();
          await summaryRelease?.future;
          // Current host opts into v5; adapt only the retained envelope version.
          return reply({
            ...sqlFixture('execution-summary'),
            'contract_version': 5,
          });
        }
        if (rpc == pageRpc) {
          return reply({
            ...sqlFixture('execution-observations'),
            'contract_version': 5,
          });
        }
        throw StateError('Unallowlisted synthetic RPC $rpc');
      }),
    );
    await installRecordedAuthFixture(
      client,
      email: 'operator@example.invalid',
      token: 'synthetic-mount',
      type: CollectOtpType.email,
    );
    legacy.session = adminSessionKey(client.auth.currentSession);
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => execution.now),
      ],
    );
    await container.read(adminIdentityProvider.future);
    controller = AdminReceiptSuccessorController(
      api: AdminReceiptSuccessorSdk(
        rpc: (name, params) async {
          if (name == 'admin_list_receipt_successors_v1') {
            final more = params['p_after'] != null;
            if (more && denyParentPage) {
              throw const CollectApiException(
                message: 'Synthetic denial',
                code: '42501',
              );
            }
            if (more && timeoutParentPage) {
              throw TimeoutException('Synthetic timeout');
            }
            return history(more: more);
          }
          return legacy.rpc(name, params);
        },
        isCurrent: () => legacy.current,
        currentSession: () => legacy.session,
        canManage: () => false,
        now: () => legacy.now,
      ),
      ownerDigest: legacy.owner,
      store: MemoryStore(),
      isCurrent: () => legacy.current,
    );
  }

  Widget app({
    bool read = true,
    String? source,
    String? selectedApproval,
    double scale = 1,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: CollectTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SingleChildScrollView(
            child: AdminReceiptSuccessorView(
              outboxId: legacy.outbox,
              sourceSnapshotId: source ?? legacy.source,
              selectedApprovalId: selectedApproval,
              controller: controller,
              canRead: read,
              canManage: false,
              now: () => legacy.now,
            ),
          ),
        ),
      ),
    ),
  );
  List<http.Request> calls(String rpc) =>
      requests.where((r) => r.url.path == '/v1/rpc/$rpc').toList();
  Future<void> close() async {
    controller.dispose();
    container.dispose();
    await client.dispose();
  }
}

Future<void> settle(WidgetTester tester) async {
  // Allow asynchronous Cloudflare client replies to complete outside widget fake time.
  for (var step = 0; step < 50; step++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<void> selectFirst(WidgetTester tester) async {
  final selector = find.text('Investigate execution').first;
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await settle(tester);
}

Map<String, dynamic> sqlFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/callback_deadlines/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

class DeadlineExecutionFixture {
  final original = AdminReceiptSuccessorExecutionSnapshot.parse(
    sqlFixture('execution-summary'),
    sqlFixture('execution-summary')['approval_id'] as String,
    sqlFixture('execution-summary')['primary_receipt_id'] as String,
  );
  late final String approval = original.approvalId,
      root = original.primaryReceiptId!;
  DateTime now = DateTime.parse(
    sqlFixture('execution-summary')['checked_at'] as String,
  );
}
