import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_view.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';
import 'support/successor_fixture.dart';

Widget app(
  SuccessorFixture f,
  AdminReceiptSuccessorController controller, {
  bool canRead = true,
  bool manage = true,
  double scale = 1,
}) => MaterialApp(
  theme: CollectTheme.light(),
  home: RepaintBoundary(
    key: const ValueKey('successor-review-render'),
    child: Scaffold(
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
  ),
);
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'operator review exposes headings, labelled reason and keyboard dismissal with actual rendered captures',
    (tester) async {
      final f = SuccessorFixture();
      final c = AdminReceiptSuccessorController(
        api: f.sdk,
        ownerDigest: f.owner,
        store: MemoryStore(),
        isCurrent: () => f.current,
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() async {
        final loader = FontLoader('Inter')
          ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
        await loader.load();
      });
      await tester.pumpWidget(app(f, c));
      await settle(tester);
      expect(
        tester
            .getSemantics(find.text('Replacement receipt review'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('successor-review-render')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('../proof-artifacts')
          ..createSync(recursive: true);
        File(
          '${output.path}/receipt-review-1440.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      debugPrint('Actual Inter review capture completed.');
      await tester.ensureVisible(find.text('Review replacement'));
      await tester.tap(find.text('Review replacement'));
      await settle(tester);
      debugPrint('Review dialog settled.');
      expect(
        find.widgetWithText(TextField, 'Reason for this review'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Reason for this review')),
        findsWidgets,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      debugPrint('Escape dismissal settled.');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        f.calls.where((x) => x.name == 'admin_approve_receipt_successor_v1'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
  testWidgets(
    'new receipt context cancels old pagination without a stuck busy state',
    (tester) async {
      final old = SuccessorFixture(),
          next = SuccessorFixture()
            ..outboxOverride = '99780000-0000-4000-8000-000000081001'
            ..sourceOverride = '99780000-0000-4000-8000-000000081002';
      final delayed = Completer<Object?>();
      Map<String, dynamic> page(SuccessorFixture f, bool more) {
        final row = clone(
          Map<String, dynamic>.from(
            observed('lineage_pages')[more ? 'next' : 'first'] as Map,
          ),
        );
        final template = Map<String, dynamic>.from(
          (row['items'] as List).first as Map,
        );
        row['outbox_id'] = f.outbox;
        row['items'] = List.generate(more ? 1 : 20, (i) {
          final item = clone(template);
          item['sequence'] = more ? 21 : i + 1;
          item['approval_id'] =
              '99780000-0000-4000-8000-${(82000 + (more ? 21 : i)).toString().padLeft(12, '0')}';
          item['outbox_id'] = f.outbox;
          (item['preview'] as Map)['root_outbox_id'] = f.outbox;
          (item['preview'] as Map)['source_snapshot_id'] = f.source;
          return item;
        });
        row['has_more'] = !more;
        row['next_after'] = more ? null : 20;
        return row;
      }

      AdminReceiptSuccessorController controller(
        SuccessorFixture f,
        bool slow,
      ) => AdminReceiptSuccessorController(
        api: AdminReceiptSuccessorSdk(
          rpc: (name, params) async {
            if (name == 'admin_list_receipt_successors_v1') {
              f.calls.add((name: name, params: params));
              return params['p_after'] == null
                  ? page(f, false)
                  : slow
                  ? delayed.future
                  : page(f, true);
            }
            return f.rpc(name, params);
          },
          isCurrent: () => f.current,
          currentSession: () => f.session,
          canManage: () => f.manage,
          now: () => f.now,
        ),
        ownerDigest: f.owner,
        store: MemoryStore(),
        isCurrent: () => f.current,
      );
      final a = controller(old, true), b = controller(next, false);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(app(old, a));
      await settle(tester);
      await tester.ensureVisible(find.text('Load more approvals'));
      await tester.tap(find.text('Load more approvals'));
      await settle(tester);
      expect(find.text('Loading history…'), findsOneWidget);
      await tester.pumpWidget(app(next, b));
      await settle(tester);
      expect(find.text('Loading history…'), findsNothing);
      expect(find.text('Load more approvals'), findsOneWidget);
      delayed.complete(page(old, true));
      await settle(tester);
      expect(find.text('Approval 21 · pending'), findsNothing);
      await tester.ensureVisible(find.text('Load more approvals'));
      await tester.tap(find.text('Load more approvals'));
      await settle(tester);
      expect(find.text('Approval 21 · pending'), findsOneWidget);
      expect(
        next.calls
            .where((c) => c.name == 'admin_inspect_receipt_successor_v1')
            .single
            .params['p_outbox_id'],
        next.outbox,
      );
      expect(
        next.calls
            .where((c) => c.name == 'admin_inspect_receipt_successor_v1')
            .single
            .params['p_source_snapshot_id'],
        next.source,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a review opened on the old receipt cannot submit after controller replacement',
    (tester) async {
      final old = SuccessorFixture(),
          next = SuccessorFixture()
            ..outboxOverride = '99780000-0000-4000-8000-000000083001'
            ..sourceOverride = '99780000-0000-4000-8000-000000083002';
      final a = AdminReceiptSuccessorController(
        api: old.sdk,
        ownerDigest: old.owner,
        store: MemoryStore(),
        isCurrent: () => old.current,
      );
      final b = AdminReceiptSuccessorController(
        api: next.sdk,
        ownerDigest: next.owner,
        store: MemoryStore(),
        isCurrent: () => next.current,
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(app(old, a));
      await settle(tester);
      await tester.ensureVisible(find.text('Review replacement'));
      await tester.tap(find.text('Review replacement'));
      await settle(tester);
      await tester.pumpWidget(app(next, b));
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('current receipt access changed'),
        findsOneWidget,
      );
      expect(find.textContaining('+250***'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve replacement receipt'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Approve replacement receipt'),
      );
      await settle(tester);
      expect(
        [
          ...old.calls,
          ...next.calls,
        ].where((c) => c.name == 'admin_approve_receipt_successor_v1'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
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
      await tester.pump();
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
      await tester.pump();
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
      await tester.pump();
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
