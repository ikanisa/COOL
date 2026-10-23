// Actual parent/host/providers/repository consumers over the declared 0700
// fixture adapter. Auth identity and transport remain synthetic; the retained
// producer files are unchanged. Existing mounted Auth/HTTP tests also cover v5.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_host.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'support/successor_fixture.dart';
import 'support/successor_retry_fixture.dart';

class RetrySession extends AdminSessionController {
  RetrySession(RetryFixture f) : super(null) {
    state = (key: f.session!, generation: 1);
  }
}

class RetryRepository extends AdminRepository {
  RetryRepository(this.fixture, this.store) : super(null);
  final RetryFixture fixture;
  final MemoryStore store;
  @override
  Future<Map<String, dynamic>> rpcMap(
    String name, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    expect(automaticRetry, isFalse);
    if (name == 'admin_approve_receipt_successor_retry_v2') {
      final saved = store.read(fixture.owner)!;
      expect(saved, contains(params!['p_request_id'] as String));
      expect(saved, contains(fixture.predecessor));
      expect(
        saved,
        isNot(contains(fixture.inspection['preview']['body'] as String)),
      );
    }
    return Map<String, dynamic>.from(
      await fixture.rpc(name, params ?? {}) as Map,
    );
  }
}

Widget host(
  RetryFixture f,
  MemoryStore store, {
  bool read = true,
  bool manage = true,
  double scale = 1,
}) => ProviderScope(
  key: ValueKey((f, read, manage)),
  overrides: [
    adminRepositoryProvider.overrideWithValue(RetryRepository(f, store)),
    adminAuthSessionScopeProvider.overrideWith((ref) => RetrySession(f)),
    adminClockProvider.overrideWithValue(() => f.now),
    adminReceiptSuccessorStoreProvider.overrideWithValue(store),
    adminIdentityProvider.overrideWith(
      (ref) async => AdminIdentity(
        userId: f.session!.userId,
        displayName: 'Synthetic retry reviewer',
        roles: ['platform_owner'],
        permissions: [
          'payments.read',
          'notifications.read',
          if (read) 'system_health.read',
          if (manage) 'notifications.manage',
        ],
      ),
    ),
  ],
  child: RepaintBoundary(
    key: const ValueKey('receipt-retry-render'),
    child: MaterialApp(
      theme: CollectTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminReceiptSuccessorHost(
            outboxId: f.root,
            sourceSnapshotId: f.source,
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

Future<void> inspect(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Inspect retry after stop'));
  await tester.tap(find.text('Inspect retry after stop'));
  await settle(tester);
}

void main() {
  testWidgets(
    'actual mounted owner inspects retired v5 route and reviews v2 immutable copy',
    (tester) async {
      final f = RetryFixture();
      final store = MemoryStore();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(f, store));
      await settle(tester);
      expect(find.text('Review next retry'), findsNothing);
      await inspect(tester);
      expect(
        find.textContaining('2 prior attempts were permanently stopped'),
        findsOneWidget,
      );
      expect(
        f.calls.map((c) => c.name),
        containsAllInOrder([
          'admin_get_receipt_successor_execution_v5',
          'admin_inspect_receipt_successor_retry_v2',
        ]),
      );
      await tester.ensureVisible(find.text('Review next retry'));
      expect(
        tester.getSemantics(find.text('Review next retry')).label,
        contains('Review next retry'),
      );
      await tester.tap(find.text('Review next retry'));
      await settle(tester);
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(f.inspection['preview']['body'] as String),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Reason for this review')),
        findsWidgets,
      );
      await tester.enterText(
        find.byType(TextField),
        'Reviewed stopped predecessor and immutable current copy',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve next retry'));
      await settle(tester);
      expect(
        f.calls.where(
          (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
        ),
        hasLength(1),
      );
      expect(store.read(f.owner), isNull);
      expect(
        f.calls.where(
          (c) =>
              c.name.contains('grant') ||
              c.name.contains('enqueue') ||
              c.name.contains('send'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'mounted unknown approval checks original v2 UUID without reapproving',
    (tester) async {
      final f = RetryFixture()..lostResponse = true;
      final store = MemoryStore();
      await tester.pumpWidget(host(f, store));
      await settle(tester);
      await inspect(tester);
      await tester.ensureVisible(find.text('Review next retry'));
      await tester.tap(find.text('Review next retry'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField),
        'Reviewed stopped predecessor and recorded balance',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve next retry'));
      await settle(tester);
      expect(store.read(f.owner), isNotNull);
      expect(find.textContaining('Original request ID:'), findsOneWidget);
      await tester.ensureVisible(find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await settle(tester);
      expect(
        f.calls.where(
          (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
        ),
        hasLength(1),
      );
      expect(
        f.calls.where(
          (c) => c.name == 'admin_get_receipt_successor_retry_request_v2',
        ),
        hasLength(1),
      );
      expect(store.read(f.owner), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mounted execution investigation uses v5 ordinary host and observations',
    (tester) async {
      final f = RetryFixture();
      await tester.pumpWidget(host(f, MemoryStore(), manage: false));
      await settle(tester);
      expect(find.text('Inspect retry after stop'), findsNothing);
      await tester.ensureVisible(find.text('Investigate execution'));
      await tester.tap(find.text('Investigate execution'));
      await settle(tester);
      expect(
        f.calls.map((c) => c.name),
        containsAll([
          'admin_get_receipt_successor_execution_v5',
          'admin_list_receipt_successor_observations_v5',
        ]),
      );
      expect(
        find.textContaining('Revoked before final authority'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('denied retry inspection erases previous preview and history', (
    tester,
  ) async {
    final f = RetryFixture()
      ..inspectionError = const CollectApiException(
        message: 'Synthetic permission revoked',
        code: '42501',
      );
    await tester.pumpWidget(host(f, MemoryStore()));
    await settle(tester);
    await inspect(tester);
    expect(
      find.textContaining('Current receipt review access is denied'),
      findsOneWidget,
    );
    expect(find.text('Review next retry'), findsNothing);
    expect(find.text('Inspect retry after stop'), findsNothing);
    expect(find.text(f.inspection['preview']['body'] as String), findsNothing);
    expect(
      f.calls.where(
        (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'compact enlarged review retains reason label and keyboard escape',
    (tester) async {
      final f = RetryFixture();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(f, MemoryStore(), scale: 1.6));
      await settle(tester);
      await inspect(tester);
      await tester.ensureVisible(find.text('Review next retry'));
      await tester.tap(find.text('Review next retry'));
      await settle(tester);
      expect(
        find.widgetWithText(TextField, 'Reason for this review'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Reason for this review')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        f.calls.where(
          (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('expired review disables confirmation without submitting', (
    tester,
  ) async {
    final f = RetryFixture();
    await tester.pumpWidget(host(f, MemoryStore()));
    await settle(tester);
    await inspect(tester);
    await tester.ensureVisible(find.text('Review next retry'));
    await tester.tap(find.text('Review next retry'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextField),
      'Reviewed stopped source before its sample expired',
    );
    f.now = DateTime.parse(f.inspection['sample_valid_until'] as String);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Review expired or current receipt access changed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve next retry'),
          )
          .onPressed,
      isNull,
    );
    expect(
      f.calls.where(
        (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
      ),
      isEmpty,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late inspection is discarded after mounted access loss', (
    tester,
  ) async {
    final f = RetryFixture()
      ..executionEntered = Completer<void>()
      ..executionRelease = Completer<void>();
    final store = MemoryStore();
    await tester.pumpWidget(host(f, store));
    await settle(tester);
    await tester.ensureVisible(find.text('Inspect retry after stop'));
    await tester.tap(find.text('Inspect retry after stop'));
    await tester.pump();
    expect(f.executionEntered!.isCompleted, isTrue);
    await tester.pumpWidget(host(f, store, read: false));
    await settle(tester);
    f.executionRelease!.complete();
    await settle(tester);
    expect(find.text('Review next retry'), findsNothing);
    expect(
      f.calls.where(
        (c) => c.name == 'admin_inspect_receipt_successor_retry_v2',
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'actual Inter retry review and dialog produce desktop and compact captures',
    (tester) async {
      final f = RetryFixture();
      final store = MemoryStore();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final fonts = FontLoader('Inter')
          ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
        await fonts.load();
      });
      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('receipt-retry-render')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('../proof-artifacts')
            ..createSync(recursive: true);
          File(
            '${directory.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(host(f, store));
      await settle(tester);
      await inspect(tester);
      await tester.ensureVisible(find.text('Review next retry'));
      await settle(tester);
      await capture('receipt-retry-1440');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(host(f, store, scale: 1.6));
      await settle(tester);
      await inspect(tester);
      await tester.ensureVisible(find.text('Review next retry'));
      await tester.tap(find.text('Review next retry'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture('receipt-retry-dialog-390');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
