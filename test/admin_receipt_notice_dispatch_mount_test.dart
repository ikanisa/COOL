import 'support/recorded_auth_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_host.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_view.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'admin_receipt_notice_dispatch_test.dart'
    show prepared, approveIntent, DispatchMemory;
import 'support/receipt_notice_dispatch_fixtures.dart';

/// Declared synthetic Auth/HTTP adapter through the actual repository/providers.
/// Actual SQL fixture IDs/content remain unchanged. Only caller request UUID is
/// adapted in mutation responses, as declared by this HTTP test harness.
class _Harness {
  _Harness({this.configuration = false, this.noStore = false})
    : now = DateTime.parse(
        dispatchFixture(
              configuration ? 'configuration-default' : 'dispatch-copy',
            )['checked_at']
            as String,
      ).add(const Duration(seconds: 1));
  final bool configuration, noStore;
  DateTime now;
  final reference = prepared(),
      memory = DispatchMemory(),
      requests = <http.Request>[];
  bool owner = true, manage = true, existingApproval = false;
  Completer<void>? release;
  late CollectCloudflareClient client;
  late ProviderContainer container;
  List<http.Request> calls(String name) =>
      requests.where((e) => e.url.path.endsWith('/$name')).toList();
  Future<void> start() async {
    await memory.store.preservePrepared(reference);
    if (existingApproval) {
      final intent = approveIntent(reference);
      await memory.store.savePending(intent);
      await memory.store.complete(
        intent,
        AdminReceiptNoticeDispatchRequest.recorded(
          dispatchFixture('approved-copy'),
          intent,
        ),
      );
      now = DateTime.parse(
        dispatchFixture('pending-copy')['checked_at'] as String,
      ).add(const Duration(seconds: 1));
    }
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        http.Response reply(Object? row, [int status = 200]) => http.Response(
          jsonEncode(row),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        if (request.url.path == '/v1/auth/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': dispatchActor, 'session_id': dispatchSession, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic',
            'token_type': 'bearer',
            'user': {
              'id': dispatchActor,
              'aud': 'authenticated',
              'email': 'owner@example.invalid',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-10-03T00:00:00Z',
            },
          });
        }
        if (request.url.path == '/v1/auth/logout') return reply({});
        requests.add(request);
        final name = request.url.path.split('/').last,
            args = (jsonDecode(request.body) ?? <String, dynamic>{}) as Map;
        if (name == 'admin_current_user') {
          return reply({
            'user_id': dispatchActor,
            'display_name': 'Synthetic current owner',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': [
              'settings.read',
              'payments.read',
              'notifications.read',
              'system_health.read',
              if (manage) 'notifications.manage',
            ],
          });
        }
        if (name == 'admin_inspect_receipt_notice_dispatch_configuration_v1') {
          expect(args, isEmpty);
          await release?.future;
          return reply(dispatchFixture('configuration-default'));
        }
        if (name == 'admin_inspect_receipt_notice_dispatch_v1') {
          expect(args, {'p_prepared_review_id': reference.preparedReviewId});
          await release?.future;
          return reply(
            dispatchFixture(
              existingApproval ? 'pending-copy' : 'dispatch-copy',
            ),
          );
        }
        if (name == 'admin_configure_receipt_notice_dispatch_v1' ||
            name == 'admin_approve_receipt_notice_dispatch_v1' ||
            name == 'admin_revoke_receipt_notice_dispatch_v1') {
          final original = await memory.store.pending(
            dispatchActor,
            dispatchSession,
          );
          expect(original, isNotNull);
          expect(args, original!.parameters);
          expect(
            args.keys.any(
              (e) =>
                  e.toString().contains('body') ||
                  e.toString().contains('destination'),
            ),
            isFalse,
          );
          return reply(
            dispatchFixture(
              name.contains('configure')
                  ? 'configuration-recorded'
                  : name.contains('revoke')
                  ? 'revoked-copy'
                  : 'approved-copy',
            )..['request_id'] = original.requestId,
          );
        }
        return reply({
          'code': '42501',
          'message': 'PRIVATE_DISPATCH_CANARY',
        }, 403);
      }),
    );
    await installRecordedAuthFixture(
      client,
      type: CollectOtpType.email,
      token: 'synthetic',
      email: 'owner@example.invalid',
    );
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => now),
        adminReceiptNoticeDispatchStoreProvider.overrideWithValue(
          noStore ? null : memory.store,
        ),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Widget app({
    bool source = false,
    double scale = 1,
    String? sourceOverride,
    VoidCallback? onRecorded,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: CollectTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: configuration
              ? AdminReceiptNoticeDispatchConfigurationHost(
                  onRecorded: onRecorded,
                )
              : source
              ? AdminReceiptNoticeDispatchSourceHost(
                  outboxId: reference.outboxId,
                  sourceSnapshotId:
                      sourceOverride ?? reference.sourceSnapshotId,
                  collectionId: reference.collectionId,
                  onRecorded: onRecorded,
                )
              : AdminReceiptNoticeDispatchHost(
                  reference: reference,
                  onRecorded: onRecorded,
                ),
        ),
      ),
    ),
  );
  Future<void> close() async {
    if (release?.isCompleted == false) release!.complete();
    container.dispose();
    await client.dispose();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

Future<void> _expose(WidgetTester tester, Finder target) async {
  await tester.pump(const Duration(milliseconds: 200));
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
}

Future<void> _reason(WidgetTester tester) async {
  final f = find.byType(TextField);
  await _expose(tester, f);
  await tester.enterText(f, 'Reviewed exact recorded dispatch evidence');
}

void _onlyAllowed(_Harness h) => expect(
  h.requests.where(
    (e) => !{
      'admin_current_user',
      'admin_inspect_receipt_notice_dispatch_configuration_v1',
      'admin_inspect_receipt_notice_dispatch_v1',
      'admin_configure_receipt_notice_dispatch_v1',
      'admin_approve_receipt_notice_dispatch_v1',
      'admin_revoke_receipt_notice_dispatch_v1',
      'admin_get_receipt_notice_dispatch_request_v1',
    }.contains(e.url.path.split('/').last),
  ),
  isEmpty,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'actual configuration host reads real revision and only explicitly records a selected state',
    (t) async {
      final h = _Harness(configuration: true);
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await _settle(t);
      expect(find.text('Current configuration revision'), findsOneWidget);
      expect(find.text('Review sample valid until'), findsOneWidget);
      expect(h.calls('admin_configure_receipt_notice_dispatch_v1'), isEmpty);
      final switcher = find.byType(SwitchListTile);
      await _expose(t, switcher);
      await t.tap(switcher);
      await _reason(t);
      await _expose(t, find.text('Record dispatch configuration'));
      await t.tap(find.text('Record dispatch configuration'));
      await _settle(t);
      expect(
        h.calls('admin_configure_receipt_notice_dispatch_v1'),
        hasLength(1),
      );
      expect(
        await h.memory.store.pending(dispatchActor, dispatchSession),
        isNull,
      );
      _onlyAllowed(h);
    },
  );
  testWidgets(
    'actual source host restores exact prepared original and records one conditional approval through SDK',
    (t) async {
      final h = _Harness();
      var callbacks = 0;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(source: true, onRecorded: () => callbacks++));
      await _settle(t);
      expect(find.text(h.reference.originalRequestId), findsOneWidget);
      expect(
        find.text(h.reference.original.inspection.candidate['body'] as String),
        findsOneWidget,
      );
      expect(h.calls('admin_approve_receipt_notice_dispatch_v1'), isEmpty);
      await _reason(t);
      await _expose(t, find.text('Record conditional approval'));
      await t.tap(find.text('Record conditional approval'));
      await _settle(t);
      expect(h.calls('admin_approve_receipt_notice_dispatch_v1'), hasLength(1));
      expect(callbacks, 1);
      expect(
        (await h.memory.store.approval(h.reference))!['approval_id'],
        dispatchFixture('approved-copy')['approval_id'],
      );
      _onlyAllowed(h);
    },
  );
  testWidgets(
    'recorded approval plus current pending sample enables only exact backend-checked unarmed revocation',
    (t) async {
      final h = _Harness()..existingApproval = true;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await _settle(t);
      expect(
        find.text(dispatchFixture('approved-copy')['approval_id'] as String),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record conditional approval'),
            )
            .onPressed,
        isNull,
      );
      await _reason(t);
      await _expose(t, find.text('Revoke unarmed approval'));
      await t.tap(find.text('Revoke unarmed approval'));
      await _settle(t);
      expect(h.calls('admin_revoke_receipt_notice_dispatch_v1'), hasLength(1));
      expect(await h.memory.store.approval(h.reference), isNull);
      _onlyAllowed(h);
    },
  );
  testWidgets(
    'no prepared original is inferred from a different snapshot source',
    (t) async {
      final h = _Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(
        h.app(
          source: true,
          sourceOverride: '99780000-0000-4000-8000-000000000077',
        ),
      );
      await _settle(t);
      expect(find.byType(AdminReceiptNoticeDispatchView), findsNothing);
      expect(h.calls('admin_inspect_receipt_notice_dispatch_v1'), isEmpty);
      expect(
        find.textContaining('No prepared review is inferred'),
        findsOneWidget,
      );
      _onlyAllowed(h);
    },
  );
  testWidgets('owner loss removes dispatch body and action authority', (
    t,
  ) async {
    final h = _Harness();
    await t.runAsync(h.start);
    addTearDown(() => t.runAsync(h.close));
    await t.pumpWidget(h.app());
    await _settle(t);
    expect(find.byType(AdminReceiptNoticeDispatchView), findsOneWidget);
    h.owner = false;
    h.container.invalidate(adminIdentityProvider);
    await t.runAsync(() => h.container.read(adminIdentityProvider.future));
    await _settle(t);
    expect(find.byType(AdminReceiptNoticeDispatchView), findsNothing);
    expect(
      find.text(h.reference.original.inspection.candidate['body'] as String),
      findsNothing,
    );
    _onlyAllowed(h);
  });
  testWidgets(
    'manage permission loss leaves read-only sample and disabled decisions',
    (t) async {
      final h = _Harness()..manage = false;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await _settle(t);
      expect(find.byType(AdminReceiptNoticeDispatchView), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record conditional approval'),
            )
            .onPressed,
        isNull,
      );
      expect(h.calls('admin_approve_receipt_notice_dispatch_v1'), isEmpty);
      _onlyAllowed(h);
    },
  );
  for (final configuration in [false, true]) {
    testWidgets(
      'late ${configuration ? 'configuration' : 'dispatch'} sample after session loss never reappears',
      (t) async {
        final h = _Harness(configuration: configuration)
          ..release = Completer<void>();
        await t.runAsync(h.start);
        addTearDown(() => t.runAsync(h.close));
        await t.pumpWidget(h.app());
        await _settle(t);
        await t.runAsync(
          () => h.client.auth.signOut(scope: CollectSignOutScope.local),
        );
        await _settle(t);
        h.release!.complete();
        h.release = null;
        await _settle(t);
        expect(find.byType(AdminReceiptNoticeDispatchView), findsNothing);
        expect(h.calls('admin_approve_receipt_notice_dispatch_v1'), isEmpty);
        expect(h.calls('admin_configure_receipt_notice_dispatch_v1'), isEmpty);
        _onlyAllowed(h);
      },
    );
  }
  testWidgets(
    'durable storage absence disables configuration changes without inventing a revision',
    (t) async {
      final h = _Harness(configuration: true, noStore: true);
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await _settle(t);
      expect(find.text('Current configuration revision'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Record dispatch configuration',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Durable browser recovery is unavailable. Recording is disabled.',
        ),
        findsOneWidget,
      );
      _onlyAllowed(h);
    },
  );
  testWidgets(
    'sample expiry disables actual mounted decisions, responsive text and keyboard remain bounded',
    (t) async {
      final h = _Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      t.view.physicalSize = const Size(360, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(h.app());
      await _settle(t);
      final semantics = t.ensureSemantics();
      try {
        await _expose(t, find.text('Notice dispatch review'));
        final heading = t
            .getSemantics(find.text('Notice dispatch review'))
            .getSemanticsData();
        expect(heading.flagsCollection.isHeader, isTrue);
        expect(heading.label, contains('Notice dispatch review'));
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(FocusManager.instance.primaryFocus, isNotNull);
        h.now = DateTime.parse(
          dispatchFixture('dispatch-copy')['sample_valid_until'] as String,
        );
        await t.pump(const Duration(seconds: 1));
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  'Record conditional approval',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text(
            'The review sample expired. Refresh current dispatch evidence before recording a decision.',
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        _onlyAllowed(h);
      } finally {
        semantics.dispose();
      }
    },
  );
  for (final pair in [(360.0, 2.0), (1440.0, 1.0)]) {
    testWidgets(
      'actual font dispatch capture at ${pair.$1} with text scale ${pair.$2}',
      (t) async {
        final h = _Harness();
        await t.runAsync(h.start);
        addTearDown(() => t.runAsync(h.close));
        t.view.physicalSize = Size(pair.$1, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        const key = ValueKey('notice-dispatch-capture');
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: h.app(scale: pair.$2),
          ),
        );
        await _settle(t);
        final semantics = t.ensureSemantics();
        try {
          await _expose(t, find.text('Notice dispatch review'));
          final heading = t
              .getSemantics(find.text('Notice dispatch review'))
              .getSemanticsData();
          expect(heading.flagsCollection.isHeader, isTrue);
          expect(heading.label, contains('Notice dispatch review'));
        } finally {
          semantics.dispose();
        }
        await _expose(t, find.text('Record conditional approval'));
        expect(t.takeException(), isNull);
        final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
        const folder = String.fromEnvironment(
          'COLLECT_NOTICE_DISPATCH_CAPTURE_ROOT',
        );
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(image.width, pair.$1.toInt());
            expect(image.height, 900);
            expect(data, isNotNull);
            expect(data!.lengthInBytes, greaterThan(8));
            // Rendering stays required in normal flutter test. A bounded proof
            // runner may additionally request retained PNG artifacts.
            if (folder.isNotEmpty) {
              final out = File(
                '$folder/dispatch-${pair.$1.toInt()}-scale-${pair.$2.toInt()}.png',
              );
              await out.parent.create(recursive: true);
              await out.writeAsBytes(data.buffer.asUint8List());
            }
          } finally {
            image.dispose();
          }
        });
        _onlyAllowed(h);
      },
    );
  }
}
