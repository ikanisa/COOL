import 'package:collect_app/admin/core/cloudflare_admin_retention_inspection.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/privacy_review_fixtures.dart';

final _source = 'a' * 64, _schema = 'b' * 64, _snapshot = 'c' * 64;
final _longTableName = 'a' * 63;

CloudflareAdminRetentionContext _context() =>
    CloudflareAdminRetentionContext.parse({
      'contract_version': 1,
      'scope': 'account_retention_inspection_context',
      'source_id': _source,
      'checked_at': privacyNow.toIso8601String(),
      'valid_until': privacyNow
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'approval_granted': false,
      'erasure_completed': false,
    }, privacyNow);

Map<String, dynamic> _inventory() => {
  'contract_version': 1,
  'request_id': privacyRequest,
  'subject_id': privacyOperation,
  'source_id': _source,
  'schema_sha256': _schema,
  'snapshot_sha256': _snapshot,
  'table_counts': {
    _longTableName: 9007199254740991,
    'sessions': 12,
    'users': 1,
  },
  'object_count': 10,
  'active_hold_count': 2,
  'in_flight_unresolved': true,
  'approval_granted': false,
  'erasure_completed': false,
};

Future<void> _host(
  WidgetTester tester, {
  required CloudflareAdminRetentionInspectionApi api,
  double width = 320,
  double scale = 1,
  VoidCallback? onAccessLost,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CloudflareAdminRetentionInspectionPanel(
              api: api,
              detail: privacyDetail(),
              onAccessLost: onAccessLost ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Inspect retained scope'));
  await tester.tap(find.text('Inspect retained scope'));
  await tester.pumpAndSettle();
}

void main() {
  for (final variant in [
    (width: 320.0, scale: 1.0),
    (width: 320.0, scale: 3.2),
    (width: 1440.0, scale: 1.0),
  ]) {
    testWidgets(
      'retention facts remain dedicated table columns at ${variant.width}/${variant.scale}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var inspections = 0;
          await _host(
            tester,
            width: variant.width,
            scale: variant.scale,
            api: CloudflareAdminRetentionInspectionApi(
              rpc: (operation, body) async {
                inspections++;
                expect(operation, 'admin_inspect_account_retention_scope_v1');
                expect(body['p_request_id'], privacyRequest);
                expect(body['p_expected_source_id'], _source);
                return _inventory();
              },
              context: _context(),
              actorId: privacyActor,
              isCurrent: () => true,
              now: () => privacyNow,
            ),
          );
          expect(inspections, 1);
          final table = tester.widget<DataTable>(find.byType(DataTable));
          expect(table.columns.length, 3);
          expect(table.rows.length, 9);
          expect(table.rows.every((row) => row.cells.length == 3), isTrue);
          expect(find.byType(ListTile), findsNothing);
          expect(find.byType(ExpansionTile), findsNothing);
          for (final value in [
            'Stored objects',
            'Active legal holds',
            'Unresolved work is present in this scope.',
            _longTableName,
            '9007199254740991',
            _source,
            _schema,
            _snapshot,
          ]) {
            final fact = find.widgetWithText(SelectableText, value);
            expect(fact, findsOneWidget, reason: value);
            expect(tester.widget<SelectableText>(fact).data, value);
          }
          final scrollbar = tester.widget<Scrollbar>(
            find.descendant(
              of: find.byType(AdminDataTable),
              matching: find.byType(Scrollbar),
            ),
          );
          expect(
            scrollbar.controller!.position.maxScrollExtent,
            greaterThan(0),
          );
          final focus = tester.widget<Focus>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Focus &&
                  widget.focusNode?.debugLabel ==
                      'Admin table horizontal scrolling',
            ),
          );
          focus.focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          expect(scrollbar.controller!.offset, greaterThan(0));
          await tester.ensureVisible(find.text(_source));
          await tester.pumpAndSettle();
          expect(find.bySemanticsLabel('Value: $_source'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('expired inspection access exposes no retained facts', (
    tester,
  ) async {
    var denied = 0, inspections = 0;
    await _host(
      tester,
      onAccessLost: () => denied++,
      api: CloudflareAdminRetentionInspectionApi(
        rpc: (_, _) async {
          inspections++;
          return _inventory();
        },
        context: _context(),
        actorId: privacyActor,
        isCurrent: () => false,
        now: () => privacyNow,
      ),
    );
    expect(denied, 1);
    expect(inspections, 0);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text(_source), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified inspection stays redacted and remains recoverable', (
    tester,
  ) async {
    await _host(
      tester,
      api: CloudflareAdminRetentionInspectionApi(
        rpc: (_, _) async => {..._inventory(), 'approval_granted': true},
        context: _context(),
        actorId: privacyActor,
        isCurrent: () => true,
        now: () => privacyNow,
      ),
    );
    expect(find.byType(DataTable), findsNothing);
    expect(find.text(_source), findsNothing);
    expect(
      find.textContaining(
        'Current retained information could not be verified.',
      ),
      findsOneWidget,
    );
    expect(find.text('Inspect retained scope'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
