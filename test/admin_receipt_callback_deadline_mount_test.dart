// Actual Admin providers/repository and pinned Auth/HTTP over retained SQL DTOs.
// Authentication and transport are synthetic; no hosted or carrier claim.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_view.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'callback_deadline_mount_support.dart';

const listRpc = 'admin_list_receipt_callback_deadlines_v1';

Future<DeadlineMountedHarness> start(WidgetTester tester) async {
  await tester.runAsync(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final h = DeadlineMountedHarness();
  await tester.runAsync(h.start);
  h.execution.now = DateTime.parse(
    sqlFixture('fresh-primary-list')['checked_at'] as String,
  ).add(const Duration(seconds: 1));
  addTearDown(h.close);
  return h;
}

Widget app(DeadlineMountedHarness h, {bool parent = false, double scale = 1}) =>
    UncontrolledProviderScope(
      container: h.container,
      child: RepaintBoundary(
        key: const ValueKey('deadline-capture'),
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: parent
                    ? const AdminReceiptTelemetryCard()
                    : const AdminReceiptCallbackDeadlineCard(),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['COLLECT_CALLBACK_CAPTURE_DIR'];
  if (dir == null) return;
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('deadline-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    await File(
      '$dir/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

Future<void> refresh(WidgetTester tester) async {
  final button = find.widgetWithText(OutlinedButton, 'Refresh').last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  testWidgets(
    'actual telemetry parent mounts authenticated deadline reads independently of unavailable aggregate',
    (tester) async {
      final h = await start(tester);
      await tester.pumpWidget(app(h, parent: true));
      await settle(tester);
      expect(find.text('Callback deadlines'), findsOneWidget);
      expect(find.text('Open original receipt'), findsNWidgets(2));
      expect(h.calls(listRpc), hasLength(1));
      final request = h.calls(listRpc).single;
      expect(jsonDecode(request.body), {
        'p_protocol_family': 'primary_v2',
        'p_active': null,
        'p_limit': 20,
        'p_before_at': null,
        'p_before_case_id': null,
        'p_cursor_query_sha256': null,
      });
      expect(
        request.headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      expect(
        h.calls('admin_get_receipt_operational_telemetry_v1'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'parent-wide');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('actual family selection opens exact successor approval route', (
    tester,
  ) async {
    final h = await start(tester);
    String? opened;
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              child: AdminReceiptCallbackDeadlineCard(),
            ),
          ),
        ),
        GoRoute(
          path: '/admin/sms-receipts/:id',
          builder: (_, state) {
            opened = state.uri.toString();
            return Scaffold(body: Text(opened!));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp.router(
          theme: CollectTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Successor attempts'));
    await settle(tester);
    expect(h.calls(listRpc), hasLength(2));
    final row =
        (sqlFixture('fresh-successor-list')['rows'] as List).first as Map;
    final button = find.text('Open selected approval').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
    expect(
      Uri.parse(opened!).path,
      '/admin/sms-receipts/${row['root_receipt_id']}',
    );
    expect(Uri.parse(opened!).queryParameters, {
      'successor_approval': row['approval_id'],
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'server denial clears authenticated retained evidence without automatic retry',
    (tester) async {
      final h = await start(tester);
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(find.text('Open original receipt'), findsNWidgets(2));
      h.deadlineDenied = true;
      await refresh(tester);
      expect(find.text('Open original receipt'), findsNothing);
      expect(
        find.text('Current investigation access is required.'),
        findsOneWidget,
      );
      expect(h.calls(listRpc), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'transport timeout allows one explicit refreshed read without blind retry',
    (tester) async {
      final h = await start(tester);
      h.deadlineTimeout = true;
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(
        find.text('Evidence could not be refreshed. Try again.'),
        findsOneWidget,
      );
      expect(h.calls(listRpc), hasLength(1));
      h.deadlineTimeout = false;
      await refresh(tester);
      expect(h.calls(listRpc), hasLength(2));
      expect(find.text('Open original receipt'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'held old-session response cannot republish protected rows after sign-out',
    (tester) async {
      final h = await start(tester);
      h.deadlineEntered = Completer<void>();
      h.deadlineRelease = Completer<void>();
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(h.deadlineEntered!.isCompleted, isTrue);
      await tester.runAsync(h.client.auth.signOut);
      await settle(tester);
      h.deadlineRelease!.complete();
      await settle(tester);
      expect(find.text('Open original receipt'), findsNothing);
      expect(
        find.text('Current receipt investigation access is required.'),
        findsOneWidget,
      );
      expect(h.calls(listRpc), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current role loss removes the actual provider and retained rows',
    (tester) async {
      final h = await start(tester);
      await tester.pumpWidget(app(h));
      await settle(tester);
      h.owner = false;
      h.container.invalidate(adminIdentityProvider);
      await settle(tester);
      expect(find.text('Open original receipt'), findsNothing);
      expect(
        find.text('Current receipt investigation access is required.'),
        findsOneWidget,
      );
      expect(h.calls(listRpc), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow enlarged text retains named controls and expired reads disable evidence navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await start(tester);
      await tester.pumpWidget(app(h, scale: 2));
      await settle(tester);
      expect(find.text('Open original receipt'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await capture(tester, 'narrow-2x');
      h.execution.now = h.execution.now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Open original receipt').first,
      );
      expect(button.onPressed, isNull);
      expect(
        find.text(
          'This read has expired. Refresh before opening evidence or actions.',
        ),
        findsOneWidget,
      );
      expect(h.calls(listRpc), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
