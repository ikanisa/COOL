import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_view.dart';
import 'support/successor_fixture.dart';

Widget app(
  SuccessorFixture f,
  AdminReceiptSuccessorController controller, {
  bool canRead = true,
  bool manage = true,
  double scale = 1,
}) => MaterialApp(
  theme: CollectTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: AdminReceiptSuccessorView(
          outboxId: f.outbox,
          sourceSnapshotId: f.source,
          controller: controller,
          canRead: canRead,
          canManage: manage,
          now: () => f.now,
        ),
      ),
    ),
  ),
);
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('denied review hides text and never reads private evidence', (
    tester,
  ) async {
    final f = SuccessorFixture();
    final c = AdminReceiptSuccessorController(
      api: f.sdk,
      ownerDigest: f.owner,
      store: MemoryStore(),
      isCurrent: () => true,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(f, c, canRead: false));
    await settle(tester);
    expect(f.calls, isEmpty);
    expect(find.textContaining('+250***'), findsNothing);
    expect(find.text('Review replacement'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'manual closure and separate replacement review retain exact text and reason',
    (tester) async {
      final f = SuccessorFixture()..closed = false;
      final c = AdminReceiptSuccessorController(
        api: f.sdk,
        ownerDigest: f.owner,
        store: MemoryStore(),
        isCurrent: () => true,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(f, c));
      await settle(tester);
      await tester.tap(find.text('Review closure'));
      await settle(tester);
      expect(
        find.textContaining('This original receipt will remain closed'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Reviewed original unarmed evidence',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Close original receipt'),
      );
      await settle(tester);
      expect(
        f.calls.where((x) => x.name == 'admin_close_unarmed_receipt_v1').length,
        1,
      );
      expect(find.text('Review replacement'), findsOneWidget);
      await tester.ensureVisible(find.text('Review replacement'));
      await tester.tap(find.text('Review replacement'));
      await settle(tester);
      final body = (f.previewRow()['preview'] as Map)['body'] as String;
      expect(find.text(body), findsWidgets);
      await tester.enterText(
        find.byType(TextField),
        'Reviewed exact recorded balance and text',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Approve replacement receipt'),
      );
      await settle(tester);
      expect(
        f.calls
            .where((x) => x.name == 'admin_approve_receipt_successor_v1')
            .length,
        1,
      );
      expect(
        find.textContaining('No financial or send action'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'uncertain response shows original lookup and never another approval',
    (tester) async {
      final f = SuccessorFixture()..timeout = true;
      final c = AdminReceiptSuccessorController(
        api: f.sdk,
        ownerDigest: f.owner,
        store: MemoryStore(),
        isCurrent: () => true,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(f, c));
      await settle(tester);
      await tester.ensureVisible(find.text('Review replacement'));
      await tester.tap(find.text('Review replacement'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField),
        'Reviewed current financial evidence',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Approve replacement receipt'),
      );
      await settle(tester);
      expect(find.textContaining('response is uncertain'), findsOneWidget);
      await tester.ensureVisible(find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await settle(tester);
      expect(find.textContaining('outcome remains unresolved'), findsOneWidget);
      expect(
        f.calls
            .where((x) => x.name == 'admin_approve_receipt_successor_v1')
            .length,
        1,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review replacement'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'expired sample hides prospective copy and enlarged compact review has no overflow',
    (tester) async {
      final f = SuccessorFixture();
      final c = AdminReceiptSuccessorController(
        api: f.sdk,
        ownerDigest: f.owner,
        store: MemoryStore(),
        isCurrent: () => true,
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(f, c, scale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
      f.now = f.now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('Replacement inspection expired'),
        findsOneWidget,
      );
      expect(find.textContaining('+250***'), findsNothing);
      expect(find.text('Review replacement'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('permission removal hides prospective and historical evidence', (
    tester,
  ) async {
    final f = SuccessorFixture();
    final c = AdminReceiptSuccessorController(
      api: f.sdk,
      ownerDigest: f.owner,
      store: MemoryStore(),
      isCurrent: () => f.current,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(f, c));
    await settle(tester);
    expect(find.textContaining('+250***'), findsWidgets);
    f.current = false;
    await tester.pumpWidget(app(f, c, canRead: false, manage: false));
    await settle(tester);
    expect(find.textContaining('+250***'), findsNothing);
    expect(find.text('Review replacement'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
