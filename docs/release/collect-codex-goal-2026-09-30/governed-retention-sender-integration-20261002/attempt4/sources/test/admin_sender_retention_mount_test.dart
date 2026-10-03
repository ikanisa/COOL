// Canonical Settings/card -> providers -> repository -> pinned Auth/PostgREST.
// HTTP and Auth are synthetic. Retention read/recovery bytes are retained SQL
// producer fixtures; generated-request replies and the second active gateway
// are declared adaptations for caller testing, not new hosted/SQL evidence.
import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_sender_picker.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_sender_retention_host.dart';
import 'package:collect_app/admin/core/admin_sender_retention_view.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_receipt_operations_checkpoint_test.dart'
    show MemoryOperationsStore;
import 'support/retention_api_fixture.dart' show Store;
import 'support/retention_fixture.dart' as f;
import 'support/admin_receipt_operations_fixture.dart' as op;

const readRpc = 'admin_get_receipt_retention_controls_v1';
const configureRpc = 'admin_configure_receipt_retention_controls_v1';
const lookupRpc = 'admin_get_receipt_retention_control_request_v1';
const gatewayRpc = 'admin_list_gateway_devices_v1';
const policyRpc = 'admin_get_receipt_operations_policy_v2';
const policyConfigureRpc = 'admin_configure_receipt_operations_v2';
const stopRpc = 'admin_stop_receipt_operations_v2';

class MountedRetentionHarness {
  final store = Store(), operationsStore = MemoryOperationsStore();
  final requests = <http.Request>[];
  final permissions = <String>{
    'settings.read',
    'settings.manage',
    'audit.read',
    'admin_users.manage',
    'notifications.manage',
    'notifications.read',
    'system_health.read',
  };
  late SupabaseClient client;
  late ProviderContainer container;
  DateTime now = f.fixtureNow;
  bool owner = true, denyRead = false, uncertainConfigure = false;
  bool gatewayDenied = false;
  Completer<void>? readEntered, readRelease;
  final gateway = f.decoded(f.gatewayActiveRaw);
  final policy = op.operationsPolicyFixture();

  List<http.Request> calls(String name) =>
      requests.where((r) => r.url.path == '/rest/v1/rpc/$name').toList();

  void senderFixture({bool twoActive = false}) {
    now = DateTime.parse(
      gateway['checked_at'] as String,
    ).add(const Duration(milliseconds: 1));
    gateway['limit'] = 50;
    final rows = gateway['rows'] as List;
    if (twoActive) {
      final first = rows.first as Map;
      first['state'] = 'active';
      first['activated_at'] = first['enrolled_at'];
      first['last_owner_action'] = null;
    }
    final active = rows.where((r) => r['state'] == 'active').toList();
    policy['checked_at'] = operationsUtc(now);
    policy['updated_at'] = operationsUtc(
      now.subtract(const Duration(seconds: 1)),
    );
    policy['device_ids'] = active.map((r) => r['device_id']).toList();
    policy['principal_ids'] = [op.operationsPrincipal];
    policy['collection_ids'] = [op.operationsCollection];
    policy['caps'] = op.operationsCaps().toJson();
  }

  Future<void> start() async {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        http.Response reply(Object body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: r,
        );
        http.Response denied() => reply({
          'code': '42501',
          'message': 'PRIVATE_RETENTION_CANARY',
          'details': null,
          'hint': null,
        }, 403);
        if (r.url.path == '/auth/v1/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': f.actor, 'session_id': f.session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': f.actor,
              'aud': 'authenticated',
              'email': 'operator@example.invalid',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-10-02T00:00:00Z',
            },
          });
        }
        if (r.url.path == '/auth/v1/logout') return reply({});
        requests.add(r);
        final name = r.url.path.split('/').last;
        if (name == 'admin_current_user') {
          return reply({
            'user_id': f.actor,
            'display_name': 'Synthetic owner',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': permissions.toList(),
          });
        }
        if (name == 'admin_runtime_config') {
          return reply({'navigation_items': [], 'queue_specs': []});
        }
        // Independent existing Settings catalog denial must not authorize or
        // prevent the separately guarded retention workspace from loading.
        if (name == 'admin_list_runtime_controls_v2') return denied();
        if (name == readRpc) {
          readEntered?.complete();
          await readRelease?.future;
          if (denyRead) return denied();
          return reply({
            ...f.decoded(f.readInitialRaw),
            'mutation_allowed': permissions.contains('settings.manage'),
          });
        }
        if (name == configureRpc) {
          final i = store.value!;
          expect(jsonDecode(r.body), i.parameters);
          expect(store.writes, 1); // durable write/readback precedes RPC
          if (uncertainConfigure)
            throw TimeoutException('Synthetic lost reply');
          final result = f.decoded(f.recordedRaw);
          result['request_id'] = i.requestId;
          result['intent'] = i.row;
          result['fingerprint_sha256'] = i.fingerprint;
          final after = result['after_configuration'] as Map;
          after['enabled'] = i.row['enabled'];
          after['batch_limit'] = i.row['batch_limit'];
          after['byte_limit'] = i.row['byte_limit'];
          return reply(result);
        }
        if (name == lookupRpc) return reply(f.decoded(f.recoveredRaw));
        if (name == gatewayRpc)
          return gatewayDenied ? denied() : reply(gateway);
        if (name == policyRpc) return reply(policy);
        if (name == policyConfigureRpc || name == stopRpc) {
          expect(operationsStore.originals, hasLength(1));
          final p = jsonDecode(r.body) as Map;
          return reply({
            'contract_version': 2,
            'request_id': p['p_request_id'],
            'revision': (p['p_expected_revision'] as int) + 1,
            'mode': name == stopRpc ? 'Paused' : p['p_mode'],
            'emergency_stop': name == stopRpc ? true : p['p_emergency_stop'],
            'recorded_at': operationsUtc(now),
            'expires_at': p['p_expires_at'],
          });
        }
        throw StateError('Unallowlisted synthetic RPC $name');
      }),
    );
    await client.auth.verifyOTP(
      email: 'operator@example.invalid',
      token: 'synthetic-mount',
      type: OtpType.email,
    );
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => now),
        adminRetentionStoreProvider.overrideWithValue(store),
        adminReceiptOperationsCheckpointStoreProvider.overrideWithValue(
          operationsStore,
        ),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Widget app({bool operations = false, double scale = 1}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: operations
                  ? const SingleChildScrollView(
                      child: AdminReceiptOperationsCard(),
                    )
                  : const AdminGovernedSettingsPage(),
            ),
          ),
        ),
      );

  Future<void> close() async {
    if (readRelease != null && !readRelease!.isCompleted)
      readRelease!.complete();
    container.dispose();
    await client.dispose();
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await t.pump();
}

Future<void> click(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
  await Scrollable.ensureVisible(t.element(f), alignment: 0.5);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  testWidgets(
    'authenticated Settings route mounts retention through the actual repository',
    (t) async {
      final h = MountedRetentionHarness();
      await t.runAsync(h.start);
      addTearDown(h.close);
      final router = h.container.read(adminRouterProvider);
      router.go('/admin/settings');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp.router(
            theme: CollectTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await settle(t);
      expect(find.byType(AdminGovernedSettingsPage), findsOneWidget);
      expect(find.byType(AdminSenderRetentionView), findsOneWidget);
      expect(find.text('Evidence retention'), findsOneWidget);
      expect(h.calls(readRpc), hasLength(1));
      expect(jsonDecode(h.calls(readRpc).single.body), isEmpty);
      expect(
        h.calls(readRpc).single.headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      expect(h.calls(configureRpc), isEmpty);
      expect(find.textContaining('PRIVATE_RETENTION_CANARY'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mounted original save uses one checkpoint and one non-retried RPC',
    (t) async {
      final h = MountedRetentionHarness();
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app());
      await settle(t);
      await t.enterText(
        field('Reason for change'),
        'Accountable retention control change',
      );
      await click(t, find.text('Record maintenance change'));
      expect(h.calls(configureRpc), hasLength(1));
      expect(h.store.writes, 1);
      expect(h.store.clears, 1);
      expect(h.store.value, isNull);
      expect(find.text('Recorded'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(h.calls(configureRpc), hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'uncertain mounted save retains its original without an automatic retry',
    (t) async {
      final h = MountedRetentionHarness()..uncertainConfigure = true;
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app());
      await settle(t);
      await t.enterText(
        field('Reason for change'),
        'Accountable uncertain control change',
      );
      await click(t, find.text('Record maintenance change'));
      final fingerprint = h.store.value!.fingerprint;
      expect(h.calls(configureRpc), hasLength(1));
      expect(find.text('Recover original request'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await settle(t);
      expect(h.calls(configureRpc), hasLength(1));
      expect(h.store.value!.fingerprint, fingerprint);
      expect(h.store.clears, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mounted recovery submits exact retained UUID, fingerprint and intent',
    (t) async {
      final h = MountedRetentionHarness();
      h.store.value = f.originalIntent();
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app());
      await settle(t);
      await click(t, find.text('Recover original request'));
      final i = f.originalIntent();
      expect(jsonDecode(h.calls(lookupRpc).single.body), {
        'p_request_id': i.requestId,
        'p_fingerprint_sha256': i.fingerprint,
        'p_intent': i.row,
      });
      expect(h.calls(configureRpc), isEmpty);
      expect(h.store.value, isNull);
      expect(h.store.clears, 1);
      expect(find.text('Recorded'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'read-only, denied and expired mounted controls cannot create a request',
    (t) async {
      final h = MountedRetentionHarness()
        ..permissions.remove('settings.manage');
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app());
      await settle(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record maintenance change'),
            )
            .onPressed,
        isNull,
      );
      h.denyRead = true;
      await click(t, find.widgetWithText(OutlinedButton, 'Refresh'));
      expect(find.textContaining('PRIVATE_RETENTION_CANARY'), findsNothing);
      expect(find.text('Record maintenance change'), findsNothing);
      h.denyRead = false;
      h.now = f.initial().validUntil;
      await click(t, find.widgetWithText(OutlinedButton, 'Refresh'));
      expect(find.text('Record maintenance change'), findsNothing);
      expect(h.calls(configureRpc), isEmpty);
      expect(h.store.writes, 0);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'identity loss fences a held mounted read and erases typed reason',
    (t) async {
      final h = MountedRetentionHarness();
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app());
      await settle(t);
      await t.enterText(field('Reason for change'), 'PRIVATE_DRAFT_CANARY');
      h.readEntered = Completer<void>();
      h.readRelease = Completer<void>();
      await click(t, find.widgetWithText(OutlinedButton, 'Refresh'));
      expect(h.readEntered!.isCompleted, isTrue);
      h.permissions.remove('notifications.manage');
      await t.runAsync(() async {
        h.container.invalidate(adminIdentityProvider);
        await h.container.read(adminIdentityProvider.future);
      });
      await settle(t);
      h.readRelease!.complete();
      await settle(t);
      expect(find.byType(AdminSenderRetentionView), findsNothing);
      expect(find.textContaining('PRIVATE_DRAFT_CANARY'), findsNothing);
      expect(h.calls(configureRpc), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mounted sender selection reorders only its allowlist through existing v2 policy',
    (t) async {
      final h = MountedRetentionHarness()..senderFixture(twoActive: true);
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(h.app(operations: true, scale: 2));
      await settle(t);
      final ids = List<String>.from(h.policy['device_ids'] as List);
      expect(h.calls(gatewayRpc), hasLength(1));
      expect(jsonDecode(h.calls(gatewayRpc).single.body)['p_limit'], 50);
      final picker = t.widget<AdminSenderPicker>(
        find.byType(AdminSenderPicker),
      );
      expect(picker.evidenceReady, isTrue);
      final dropdown = t.widget<DropdownButtonFormField<String>>(
        find.descendant(
          of: find.byType(AdminSenderPicker),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      dropdown.onChanged!(ids.last);
      await t.pump();
      expect(
        t
            .widget<TextField>(field('Gateway device IDs (one per line)'))
            .controller!
            .text
            .split('\n'),
        ids.reversed.toList(),
      );
      await click(t, find.text('Review and apply policy'));
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Reviewed primary Android selection',
      );
      await click(t, find.text('Apply reviewed policy'));
      expect(h.calls(policyConfigureRpc), hasLength(1));
      final sent = jsonDecode(h.calls(policyConfigureRpc).single.body) as Map;
      expect(sent['p_device_ids'], ids.reversed.toList());
      expect(sent['p_expected_revision'], h.policy['revision']);
      expect(h.operationsStore.resolutions, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sender denial blocks configuration while independent emergency stop remains usable',
    (t) async {
      final h = MountedRetentionHarness()..senderFixture();
      h.gatewayDenied = true;
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app(operations: true));
      await settle(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and apply policy'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('PRIVATE_RETENTION_CANARY'), findsNothing);
      await click(t, find.widgetWithText(OutlinedButton, 'Emergency stop'));
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Accountable independent emergency stop',
      );
      await click(t, find.text('Record emergency stop'));
      expect(h.calls(stopRpc), hasLength(1));
      expect(h.calls(policyConfigureRpc), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sender evidence expiring during review prevents a policy request',
    (t) async {
      final h = MountedRetentionHarness()..senderFixture();
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app(operations: true));
      await settle(t);
      await click(t, find.text('Review and apply policy'));
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Reviewed sender evidence must remain current',
      );
      h.now = DateTime.parse(h.gateway['sample_valid_until'] as String);
      await click(t, find.text('Apply reviewed policy'));
      expect(h.calls(policyConfigureRpc), isEmpty);
      expect(h.operationsStore.originals, isEmpty);
      expect(
        find.textContaining('Sender evidence or draft authority changed'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'duplicate pasted sender IDs remain visible and deny configuration without crashing',
    (t) async {
      final h = MountedRetentionHarness()..senderFixture();
      await t.runAsync(h.start);
      addTearDown(h.close);
      await t.pumpWidget(h.app(operations: true));
      await settle(t);
      final id = (h.policy['device_ids'] as List).single;
      await t.enterText(field('Gateway device IDs (one per line)'), '$id\n$id');
      await t.pump();
      expect(t.takeException(), isNull);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and apply policy'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextField>(field('Gateway device IDs (one per line)'))
            .controller!
            .text,
        '$id\n$id',
      );
      expect(h.calls(policyConfigureRpc), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}
