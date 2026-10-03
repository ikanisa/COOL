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
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/successor_fixture.dart';
import 'support/execution_fixture.dart';
import 'support/execution_api_fixture.dart';

const actor = '99440000-0000-4000-8000-000000000001';
const summaryRpc = 'admin_get_receipt_successor_execution_v4';
const pageRpc = 'admin_list_receipt_successor_observations_v4';

class MountedHarness {
  final execution = ExecutionFixture();
  final legacy = SuccessorFixture();
  final requests = <http.Request>[];
  late SupabaseClient client;
  late ProviderContainer container;
  late AdminReceiptSuccessorController controller;
  bool denyParentPage = false, timeoutParentPage = false;
  bool owner = true;
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
      item['approval_id'] = !more && i == 0
          ? execution.approval
          : '99440000-0000-4000-8000-${(81000 + (more ? 21 : i)).toString().padLeft(12, '0')}';
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
    legacy.outboxOverride = execution.root;
    legacy.now = execution.now;
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response reply(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        if (request.url.path == '/auth/v1/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'session_id': 'mounted-session', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
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
        if (request.url.path == '/auth/v1/logout') return reply({});
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
        if (rpc == summaryRpc) {
          summaryEntered?.complete();
          await summaryRelease?.future;
          return reply(decoded(knownSentRaw));
        }
        if (rpc == pageRpc) {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          return reply(
            ExecutionApiFixture()
                .fixturePage(
                  execution.original,
                  params['p_after_revision'] as int?,
                  params['p_limit'] as int,
                )
                .row,
          );
        }
        throw StateError('Unallowlisted synthetic RPC $rpc');
      }),
    );
    await client.auth.verifyOTP(
      email: 'operator@example.invalid',
      token: 'synthetic-mount',
      type: OtpType.email,
    );
    legacy.session = adminSessionKey(client.auth.currentSession);
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
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
              throw const PostgrestException(
                message: 'Synthetic denial',
                code: '42501',
              );
            }
            if (more && timeoutParentPage)
              throw TimeoutException('Synthetic timeout');
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

  Widget app({bool read = true, String? source, double scale = 1}) =>
      UncontrolledProviderScope(
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
      requests.where((r) => r.url.path == '/rest/v1/rpc/$rpc').toList();
  Future<void> close() async {
    controller.dispose();
    container.dispose();
    await client.dispose();
  }
}

Future<void> settle(WidgetTester tester) async {
  // The pinned PostgREST adapter decodes JSON asynchronously outside the fake
  // widget clock. Alternate finite real-zone yielding with fake-zone pumps,
  // as the retained cold-consumer caller does; never bypass that adapter.
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

void main() {
  testWidgets(
    'one selected validated approval uses real repository/session read path',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(h.app());
      await settle(tester);
      expect(find.text('Investigate execution'), findsNWidgets(20));
      expect(h.calls(summaryRpc), isEmpty);
      await selectFirst(tester);
      expect(find.text('Retry execution'), findsOneWidget);
      expect(find.text('Sent callback observed'), findsWidgets);
      expect(h.calls(summaryRpc), hasLength(1));
      expect(jsonDecode(h.calls(summaryRpc).single.body), {
        'p_approval_id': h.execution.approval,
      });
      expect(jsonDecode(h.calls(pageRpc).single.body), {
        'p_approval_id': h.execution.approval,
        'p_cutoff_revision': h.execution.original.cutoff,
        'p_after_revision': null,
        'p_limit': 20,
      });
      expect(
        h.calls(summaryRpc).single.headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      await tester.ensureVisible(find.text('Close investigation'));
      await tester.tap(find.text('Close investigation'));
      await settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(h.calls(summaryRpc), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'denied parent pagination clears review and selected execution; explicit refresh recovers',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(h.app());
      await settle(tester);
      await selectFirst(tester);
      h.denyParentPage = true;
      await tester.ensureVisible(find.text('Load more approvals'));
      await tester.tap(find.text('Load more approvals'));
      await settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(find.text('Investigate execution'), findsNothing);
      expect(
        find.textContaining('Current receipt review access is denied'),
        findsOneWidget,
      );
      h.denyParentPage = false;
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Refresh evidence'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh evidence'));
      await settle(tester);
      expect(find.text('Investigate execution'), findsNWidgets(20));
      expect(find.text('Retry execution'), findsNothing);
      await selectFirst(tester);
      expect(h.calls(summaryRpc), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('transient parent timeout retains the selected authorized page', (
    tester,
  ) async {
    final h = MountedHarness();
    await tester.runAsync(h.start);
    addTearDown(h.close);
    await tester.pumpWidget(h.app());
    await settle(tester);
    await selectFirst(tester);
    h.timeoutParentPage = true;
    await tester.ensureVisible(find.text('Load more approvals'));
    await tester.tap(find.text('Load more approvals'));
    await settle(tester);
    expect(find.text('Retry execution'), findsOneWidget);
    expect(find.text('Investigate execution'), findsNWidgets(19));
    expect(find.text('Load more approvals'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'real auth signout and departed response cannot restore protected execution',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      h.summaryEntered = Completer<void>();
      h.summaryRelease = Completer<void>();
      await tester.pumpWidget(h.app());
      await settle(tester);
      await selectFirst(tester);
      expect(h.summaryEntered!.isCompleted, isTrue);
      await tester.runAsync(() => h.client.auth.signOut());
      await settle(tester);
      h.summaryRelease!.complete();
      await settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(
        find.textContaining('Current email-owner access is required'),
        findsOneWidget,
      );
      expect(h.calls(pageRpc), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'source/read boundary changes dismount selected evidence and require a new selection',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(h.app());
      await settle(tester);
      await selectFirst(tester);
      await tester.pumpWidget(
        h.app(source: '99440000-0000-4000-8000-000000090001'),
      );
      await settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(h.calls(summaryRpc), hasLength(1));
      await tester.pumpWidget(h.app(read: false));
      await settle(tester);
      expect(find.text('Investigate execution'), findsNothing);
      expect(
        find.textContaining('Current receipt review access is required'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'owner role loss invalidates real provider authority without another read',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(h.app());
      await settle(tester);
      await selectFirst(tester);
      h.owner = false;
      h.container.invalidate(adminIdentityProvider);
      await settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(
        find.textContaining('Current email-owner access is required'),
        findsOneWidget,
      );
      expect(h.calls(summaryRpc), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'compact enlarged text and labelled keyboard selection remain usable',
    (tester) async {
      final h = MountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(h.app(scale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // First tab focuses the parent refresh, second reaches first approval.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(h.calls(summaryRpc), hasLength(1));
      expect(find.text('Retry execution'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Retry execution'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
}
