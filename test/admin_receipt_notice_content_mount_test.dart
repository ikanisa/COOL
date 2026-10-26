import 'support/recorded_auth_fixture.dart';
// Exercises the current Cloudflare client and repository with controlled HTTP replies.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_host.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_host.dart';
import 'support/receipt_notice_dispatch_journal_fixture.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_test.dart'
    show fixture, inspection, Store, actor, session;

const captureRoot = String.fromEnvironment('COLLECT_NOTICE_CAPTURE_ROOT');

class Harness {
  Harness({Map<String, dynamic>? content})
    : content = content ?? fixture('content-preview-duplicate_copy-rw');
  final store = Store(), requests = <http.Request>[];
  final permissions = <String>{
    'settings.read',
    'groups.read',
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  };
  late CollectCloudflareClient client;
  late ProviderContainer container;
  bool owner = true, deny = false, loseResponse = false, wrongWindow = false;
  int groupsTotal = 26;
  final sample = inspection('policy-preview-duplicate_copy-rw');
  late DateTime now = sample.checkedAt.add(const Duration(seconds: 1));
  final Map<String, dynamic> content;
  List<http.Request> calls(String name) =>
      requests.where((r) => r.url.path == '/v1/rpc/$name').toList();
  Future<void> start() async {
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((r) async {
        http.Response reply(Object? body, [int code = 200]) => http.Response(
          jsonEncode(body),
          code,
          headers: {'content-type': 'application/json'},
          request: r,
        );
        if (r.url.path == '/v1/auth/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': actor, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'email': 'operator@example.invalid',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-10-03T00:00:00Z',
            },
          });
        }
        if (r.url.path == '/v1/auth/logout') return reply({});
        requests.add(r);
        final name = r.url.path.split('/').last,
            params = (jsonDecode(r.body) ?? <String, dynamic>{}) as Map;
        if (name == 'admin_current_user') {
          return reply({
            'user_id': actor,
            'display_name': 'Synthetic owner',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': permissions.toList(),
          });
        }
        if (name == 'admin_list_country_scoped') {
          expect(params['p_rpc_name'], 'admin_list_collections');
          expect(params['p_country'], 'RW');
          expect(params['p_limit'], 25);
          final offset = params['p_offset'] as int,
              count = (groupsTotal - offset).clamp(0, 25);
          return reply({
            'rows': [
              for (var n = offset; n < offset + count; n++)
                {
                  'id': n == 0
                      ? sample.collectionId
                      : '99780000-0000-4000-8000-${(n + 30001).toString().padLeft(12, '0')}',
                  'title': 'Rwanda group ${n + 1}',
                  'country_code': wrongWindow ? 'FR' : 'RW',
                  'status': 'active',
                  'amount': '',
                  'subtitle': '',
                },
            ],
            'total': groupsTotal,
          });
        }
        if (deny) {
          return reply({
            'code': '42501',
            'message': 'PRIVATE_NOTICE_CANARY',
          }, 403);
        }
        if (name == 'admin_inspect_receipt_notice_policy_v1') {
          return reply(
            fixture(
              'policy-preview-${params['p_notice_family']}-${params['p_language']}',
            ),
          );
        }
        if (name == 'admin_inspect_receipt_notice_content_v1') {
          final family = params['p_notice_family'];
          return reply(
            fixture(
              family == 'correction' || family == 'approved_resend'
                  ? 'explicit-$family-refusal'
                  : 'content-preview-$family-rw',
            ),
          );
        }
        if (name == 'admin_approve_receipt_notice_policy_v1' ||
            name == 'admin_prepare_receipt_notice_content_v1') {
          final i = store.value!;
          expect(params, i.parameters);
          expect(store.events.first, 'write');
          expect(
            params.keys.any(
              (k) =>
                  k.toString().contains('body') ||
                  k.toString().contains('destination'),
            ),
            isFalse,
          );
          if (loseResponse) throw TimeoutException('Synthetic lost response');
          final result = fixture(
            i.policy
                ? 'actual-approved-policy-duplicate_copy-rw'
                : 'actual-prepared-duplicate_copy-rw',
          )..['request_id'] = i.requestId;
          return reply(result);
        }
        if (name == 'admin_get_receipt_notice_content_request_v1') {
          return reply({
            'scope': 'rw_receipt_notice_content',
            'contract_version': 1,
            'request_id': store.value!.requestId,
            'status': 'not_recorded',
            'result': null,
            'prepared_preview': null,
            'policy_template': null,
            'send_authority': false,
            'financial_action': false,
            'notice_transport_available': false,
          });
        }
        return reply({
          'code': '42501',
          'message': 'unexpected synthetic RPC',
        }, 403);
      }),
    );
    await installRecordedAuthFixture(
      client,
      type: CollectOtpType.email,
      token: 'synthetic',
      email: 'operator@example.invalid',
    );
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => now),
        adminReceiptNoticeContentStoreProvider.overrideWithValue(store),
        adminReceiptNoticeDispatchStoreProvider.overrideWithValue(
          NoticeDispatchJournalFixture().store,
        ),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Widget app({
    bool policy = true,
    bool selector = false,
    double scale = 1,
    GlobalKey? capture,
    String? reversalSnapshotId,
    String? sourceSnapshotId,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: CollectTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: capture,
            child: SingleChildScrollView(
              child: policy
                  ? AdminReceiptNoticePolicyHost(
                      collectionId: selector ? null : sample.collectionId,
                    )
                  : AdminReceiptNoticeContentHost(
                      outboxId: content['outbox_id'] as String,
                      sourceSnapshotId:
                          sourceSnapshotId ??
                          (content['candidate'] as Map)['source_snapshot_id']
                              as String,
                      collectionId: sample.collectionId,
                      reversalSnapshotId: reversalSnapshotId,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> close() async {
    container.dispose();
    await client.dispose();
  }
}

Future<void> settle(WidgetTester t) async {
  for (var n = 0; n < 20; n++) {
    await t.pump(const Duration(milliseconds: 16));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'actual owner host renders bound policy and records through no-retry repository once',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await settle(t);
      expect(h.calls('admin_inspect_receipt_notice_policy_v1'), hasLength(1));
      expect(find.text('Original recorded receipt facts only'), findsOneWidget);
      await t.enterText(
        find.byType(TextField),
        'Reviewed immutable notice evidence',
      );
      await t.ensureVisible(find.text('Record notice policy'));
      await t.tap(find.text('Record notice policy'));
      await settle(t);
      expect(h.calls('admin_approve_receipt_notice_policy_v1'), hasLength(1));
      expect(h.store.value, isNull);
      expect(
        find.text('Notice policy recorded. Refresh for current values.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'real HTTP lost response preserves checkpoint and only original lookup',
    (t) async {
      final h = Harness()..loseResponse = true;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await settle(t);
      await t.enterText(
        find.byType(TextField),
        'Reviewed immutable notice evidence',
      );
      await t.ensureVisible(find.text('Record notice policy'));
      await t.tap(find.text('Record notice policy'));
      await settle(t);
      final id = h.store.value!.requestId;
      expect(h.calls('admin_approve_receipt_notice_policy_v1'), hasLength(1));
      await t.ensureVisible(find.text('Recover original request'));
      await t.tap(find.text('Recover original request'));
      await settle(t);
      expect(h.store.value?.requestId, id);
      expect(h.calls('admin_approve_receipt_notice_policy_v1'), hasLength(1));
      expect(
        h.calls('admin_get_receipt_notice_content_request_v1'),
        hasLength(1),
      );
      expect(
        find.textContaining('replacement requests are blocked'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'content host uses exact original snapshot and immutable masked preview',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      h.now = DateTime.parse(
        h.content['checked_at'] as String,
      ).add(const Duration(seconds: 1));
      await t.pumpWidget(h.app(policy: false));
      await settle(t);
      final params =
          jsonDecode(
                h.calls('admin_inspect_receipt_notice_content_v1').single.body,
              )
              as Map;
      expect(params['p_outbox_id'], h.content['outbox_id']);
      expect(
        params['p_source_snapshot_id'],
        (h.content['candidate'] as Map)['source_snapshot_id'],
      );
      expect(
        find.text(
          (h.content['candidate'] as Map)['destination_masked'] as String,
        ),
        findsOneWidget,
      );
      expect(
        find.text((h.content['candidate'] as Map)['body'] as String),
        findsOneWidget,
      );
      expect(find.text('Save immutable notice content'), findsOneWidget);
    },
  );
  testWidgets(
    'owner/manage changes remove or disable the actual guarded controls',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await settle(t);
      h.permissions.remove('notifications.manage');
      h.container.invalidate(adminIdentityProvider);
      await t.runAsync(() => h.container.read(adminIdentityProvider.future));
      await settle(t);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.textContaining('notification manage permission'),
        findsOneWidget,
      );
      h.owner = false;
      h.container.invalidate(adminIdentityProvider);
      await t.runAsync(() => h.container.read(adminIdentityProvider.future));
      await settle(t);
      expect(
        find.textContaining('Current email-owner access and payment'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('session sign-out redacts current notice facts and actions', (
    t,
  ) async {
    final h = Harness();
    await t.runAsync(h.start);
    addTearDown(() => t.runAsync(h.close));
    await t.pumpWidget(h.app());
    await settle(t);
    await t.runAsync(
      () => h.client.auth.signOut(scope: CollectSignOutScope.local),
    );
    await settle(t);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Current email-owner access and payment'),
      findsOneWidget,
    );
    expect(h.calls('admin_approve_receipt_notice_policy_v1'), isEmpty);
  });
  testWidgets('denial never exposes server text or invents a current policy', (
    t,
  ) async {
    final h = Harness()..deny = true;
    await t.runAsync(h.start);
    addTearDown(() => t.runAsync(h.close));
    await t.pumpWidget(h.app());
    await settle(t);
    expect(find.textContaining('PRIVATE_NOTICE_CANARY'), findsNothing);
    expect(
      find.textContaining('Current email-owner access is required'),
      findsOneWidget,
    );
    expect(find.text('Record notice policy'), findsNothing);
  });
  testWidgets(
    'Rwanda selector validates bounded server pages and restores group scope',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(selector: true));
      await settle(t);
      expect(find.text('Groups 1–25 of 26'), findsOneWidget);
      await t.tap(find.text('Next groups'));
      await settle(t);
      expect(find.text('Groups 26–26 of 26'), findsOneWidget);
      expect(
        (jsonDecode(h.calls('admin_list_country_scoped').last.body)
            as Map)['p_offset'],
        25,
      );
      await t.tap(find.text('Previous groups'));
      await settle(t);
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Rwanda group 1').last);
      await settle(t);
      expect(h.calls('admin_inspect_receipt_notice_policy_v1'), hasLength(1));
    },
  );
  testWidgets(
    'foreign group response is unavailable rather than a fabricated empty list',
    (t) async {
      final h = Harness()..wrongWindow = true;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(selector: true));
      await settle(t);
      expect(
        find.textContaining('Rwanda groups could not be loaded'),
        findsOneWidget,
      );
      expect(find.textContaining('No Rwanda groups'), findsNothing);
      expect(h.calls('admin_inspect_receipt_notice_policy_v1'), isEmpty);
    },
  );
  testWidgets(
    'sample expiry disables recording without a replacement request',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await settle(t);
      await t.enterText(
        find.byType(TextField),
        'Reviewed immutable notice evidence',
      );
      h.now = h.sample.validUntil;
      await t.pump(const Duration(seconds: 1));
      expect(
        find.text('This preview has expired. Refresh before recording.'),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record notice policy'),
            )
            .onPressed,
        isNull,
      );
      expect(h.calls('admin_approve_receipt_notice_policy_v1'), isEmpty);
    },
  );
  testWidgets(
    'compensation purpose requires actual selected compensation evidence',
    (t) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      h.now = DateTime.parse(
        h.content['checked_at'] as String,
      ).add(const Duration(seconds: 1));
      await t.pumpWidget(h.app(policy: false));
      await settle(t);
      await t.tap(
        find.byType(DropdownButtonFormField<AdminReceiptNoticeFamily>).first,
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('Collect ledger compensation').last);
      await settle(t);
      expect(
        find.textContaining(
          'Verified compensation snapshot evidence is required',
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Refresh preview'),
            )
            .onPressed,
        isNull,
      );
      expect(h.calls('admin_inspect_receipt_notice_content_v1'), hasLength(1));
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
    },
  );
  testWidgets(
    'compensation host sends the selected exact snapshot and renders immutable backend facts',
    (t) async {
      final h = Harness(content: fixture('content-preview-reversal_notice-rw')),
          reversal = fixture('content-preview-reversal_notice-rw'),
          snapshot =
              (fixture('content-preview-reversal_notice-rw')['candidate']
                      as Map)['source_snapshot_id']
                  as String;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      h.now = DateTime.parse(
        reversal['checked_at'] as String,
      ).add(const Duration(seconds: 1));
      await t.pumpWidget(
        h.app(
          policy: false,
          reversalSnapshotId: snapshot,
          sourceSnapshotId:
              ((reversal['candidate'] as Map)['source_evidence']
                      as Map)['source_facts']['original_snapshot_id']
                  as String,
        ),
      );
      await settle(t);
      await t.tap(
        find.byType(DropdownButtonFormField<AdminReceiptNoticeFamily>).first,
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('Collect ledger compensation').last);
      await settle(t);
      await t.ensureVisible(find.text('Refresh preview'));
      await t.tap(find.text('Refresh preview'));
      await settle(t);
      final request =
          jsonDecode(
                h.calls('admin_inspect_receipt_notice_content_v1').last.body,
              )
              as Map;
      expect(request['p_source_snapshot_id'], snapshot);
      expect(request['p_notice_family'], 'reversal_notice');
      expect(request['p_outbox_id'], h.content['outbox_id']);
      expect(
        find.text((reversal['candidate'] as Map)['body'] as String),
        findsOneWidget,
      );
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
    },
  );
  for (final pair in [
    (
      'Correction',
      'Correction requires verified source evidence before content can be prepared.',
    ),
    (
      'Approved resend',
      'Resolve the original send outcome before an approved resend can be considered.',
    ),
  ]) {
    testWidgets('${pair.$1} displays the actual backend prerequisite refusal', (
      t,
    ) async {
      final h = Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      h.now = DateTime.parse(
        h.content['checked_at'] as String,
      ).add(const Duration(seconds: 1));
      await t.pumpWidget(h.app(policy: false));
      await settle(t);
      await t.tap(
        find.byType(DropdownButtonFormField<AdminReceiptNoticeFamily>).first,
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text(pair.$1).last);
      await settle(t);
      await t.ensureVisible(find.text('Refresh preview'));
      await t.tap(find.text('Refresh preview'));
      await settle(t);
      expect(find.text(pair.$2), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Save immutable notice content',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
    });
  }
  for (final width in [360.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'actual-font notice controls reflow and expose named keyboard controls $width/$scale',
        (t) async {
          await t.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => t.binding.setSurfaceSize(null));
          final h = Harness();
          await t.runAsync(h.start);
          addTearDown(() => t.runAsync(h.close));
          final sem = t.ensureSemantics();
          try {
            final key = GlobalKey();
            await t.pumpWidget(h.app(scale: scale, capture: key));
            await settle(t);
            expect(t.takeException(), isNull);
            expect(find.text('Notice purpose'), findsOneWidget);
            await t.ensureVisible(find.byType(TextField));
            await t.tap(find.byType(TextField));
            await t.sendKeyEvent(LogicalKeyboardKey.tab);
            await t.pump();
            expect(t.takeException(), isNull);
            expect(FocusManager.instance.primaryFocus?.context, isNotNull);
            expect(
              find.bySemanticsLabel('Reason for recording'),
              findsOneWidget,
            );
            if (captureRoot.isNotEmpty && scale == 1) {
              await t.ensureVisible(find.text('Receipt notice policy'));
              await t.pump();
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await t.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1),
                    bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                await File(
                  '$captureRoot/notice-policy-${width.toInt()}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          } finally {
            sem.dispose();
          }
        },
      );
    }
  }
}
