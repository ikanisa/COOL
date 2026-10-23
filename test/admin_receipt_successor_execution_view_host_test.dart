import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_host.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_view.dart';
import 'support/execution_fixture.dart';
import 'support/execution_api_fixture.dart';

AdminReceiptSuccessorExecutionController controller(ExecutionApiFixture api) =>
    AdminReceiptSuccessorExecutionController(
      api: api,
      approvalId: api.currentSnapshot.approvalId,
      primaryReceiptId: api.currentSnapshot.primaryReceiptId!,
      isCurrent: () => api.current,
    );
Widget view(AdminReceiptSuccessorExecutionController c, {double scale = 1}) =>
    MaterialApp(
      theme: CollectTheme.light(),
      home: RepaintBoundary(
        key: const ValueKey('execution-capture'),
        child: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: AdminReceiptSuccessorExecutionView(
                controller: c,
                now: () =>
                    c.snapshot?.checkedAt ?? snapshot(knownSentRaw).checkedAt,
              ),
            ),
          ),
        ),
      ),
    );
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class SessionFixture extends AdminSessionController {
  SessionFixture() : super(null) {
    state = (
      key: (
        userId: '00000000-0000-0000-0000-000000000001',
        sessionId: '00000000-0000-0000-0000-000000000002',
      ),
      generation: 1,
    );
  }
}

class RepositoryFixture extends AdminRepository {
  RepositoryFixture() : super(null);
  final calls = <String>[];
  final api = ExecutionApiFixture();
  @override
  Future<Map<String, dynamic>> rpcMap(
    String name, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    expect(automaticRetry, isFalse);
    calls.add(name);
    if (name == 'admin_get_receipt_successor_execution_v5') {
      return {...decoded(knownSentRaw), 'contract_version': 5};
    }
    return {
      ...api
          .fixturePage(
            api.currentSnapshot,
            params!['p_after_revision'] as int?,
            params['p_limit'] as int,
          )
          .row,
      'contract_version': 5,
    };
  }
}

void main() {
  testWidgets(
    'compact enlarged text retains labelled keyboard refresh without overflow',
    (tester) async {
      final api = ExecutionApiFixture(), c = controller(api);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(view(c, scale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      final refresh = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Refresh evidence'),
      );
      expect(refresh.onPressed, isNotNull);
      final before = api.calls.length;
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(api.calls.length, greaterThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'read-only execution shows labelled evidence semantic headings compact and wide actual-font captures',
    (tester) async {
      final api = ExecutionApiFixture(raw: lateUncertainRaw),
          c = controller(api);
      addTearDown(c.dispose);
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() async {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [1440.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(view(c));
        await settle(tester);
        expect(
          tester
              .getSemantics(find.text('Retry execution'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(find.text('Uncertain · investigation required'), findsWidgets);
        expect(
          find.textContaining('retained total is unknown'),
          findsOneWidget,
        );
        expect(find.text('Load more callback evidence'), findsOneWidget);
        expect(find.text('Send'), findsNothing);
        expect(find.text('Approve resend'), findsNothing);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('execution-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('../proof-artifacts')
            ..createSync(recursive: true);
          File(
            '${dir.path}/execution-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
  testWidgets(
    'view replaces departed approval controller while its old history request remains in flight',
    (tester) async {
      final old = ExecutionApiFixture(), a = controller(old);
      final fresh = ExecutionApiFixture(raw: unarmedRaw), b = controller(fresh);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(view(a));
      await settle(tester);
      final pending = Completer<AdminReceiptSuccessorObservationPage>();
      old.pagePending = pending;
      final future = a.more();
      await tester.pump();
      await tester.pumpWidget(view(b));
      await settle(tester);
      expect(find.text(b.approvalId), findsOneWidget);
      expect(find.text(a.approvalId), findsNothing);
      pending.complete(old.fixturePage(old.currentSnapshot, a.next, 20));
      await future;
      await tester.pump();
      expect(find.text(b.approvalId), findsOneWidget);
      expect(find.text(a.approvalId), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual host uses no-retry current-owner repository adapter and denies missing read permission',
    (tester) async {
      final repository = RepositoryFixture();
      final s = snapshot(knownSentRaw);
      Widget host(bool permitted) => ProviderScope(
        key: ValueKey(permitted),
        overrides: [
          adminRepositoryProvider.overrideWithValue(repository),
          adminAuthSessionScopeProvider.overrideWith((ref) => SessionFixture()),
          adminClockProvider.overrideWithValue(
            () => DateTime.parse(
              decoded(knownSentRaw)['checked_at'] as String,
            ).add(const Duration(seconds: 1)),
          ),
          adminIdentityProvider.overrideWith(
            (ref) async => AdminIdentity(
              userId: '00000000-0000-0000-0000-000000000001',
              displayName: 'Synthetic owner',
              roles: ['platform_owner'],
              permissions: [
                'payments.read',
                'notifications.read',
                if (permitted) 'system_health.read',
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminReceiptSuccessorExecutionHost(
                approvalId: s.approvalId,
                primaryReceiptId: s.primaryReceiptId!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await settle(tester);
      expect(
        repository.calls,
        containsAll([
          'admin_get_receipt_successor_execution_v5',
          'admin_list_receipt_successor_observations_v5',
        ]),
      );
      final count = repository.calls.length;
      await tester.pumpWidget(host(false));
      await settle(tester);
      expect(repository.calls.length, count);
      expect(find.textContaining('Current email-owner access'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('SDK applies its real fifteen-second read deadline once', (
    tester,
  ) async {
    final f = ExecutionFixture();
    var calls = 0;
    final sdk = AdminReceiptSuccessorExecutionSdk(
      rpc: (_, _) {
        calls++;
        return Completer<Object?>().future;
      },
      isCurrent: () => true,
      now: () => f.now,
    );
    final future = sdk.inspect(f.approval, f.root);
    final expectation = expectLater(future, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 16));
    await expectation;
    expect(calls, 1);
  });
}
