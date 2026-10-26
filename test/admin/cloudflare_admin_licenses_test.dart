import 'package:collect_app/admin/core/cloudflare_admin_licenses_page.dart';
import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const fullNotice =
    'Copyright 2026 Example Contributors.\n\n'
    'Permission applies to the complete work, including café and £ values.\n\n'
    'Retain this attribution and this final notice without omission.';

void main() {
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  Future<void> mount(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.adapt(AppTheme.dark()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: CloudflareAdminLicensesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('package table retains complete shared attribution and notices', (
    tester,
  ) async {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['alpha', 'zeta'], fullNotice);
      yield const LicenseEntryWithLineBreaks([
        'alpha',
      ], 'Second complete notice.');
    });
    await mount(tester);
    var table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.columns.map((c) => (c.label as Text).data), [
      'Package',
      'Notices',
      'Open',
    ]);
    expect(table.rows, hasLength(2));
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(Card), findsNothing);
    await tester.tap(find.byTooltip('Open alpha'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Packages'), findsOneWidget);
    expect(find.text('Legal notice'), findsOneWidget);
    expect(find.text('alpha\nzeta'), findsOneWidget);
    expect(find.text(fullNotice), findsOneWidget);
    expect(find.text('Second complete notice.'), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back to license index'));
    await tester.pumpAndSettle();
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.rows, hasLength(2));
  });

  testWidgets('search, sorting and filters precede 25-package pagination', (
    tester,
  ) async {
    LicenseRegistry.addLicense(() async* {
      for (var i = 0; i < 28; i++) {
        yield LicenseEntryWithLineBreaks([
          'package_${i.toString().padLeft(2, '0')}',
        ], 'Notice $i');
      }
      yield const LicenseEntryWithLineBreaks([
        'package_27',
      ], 'Additional attribution for package 27.');
    });
    await mount(tester);
    expect(find.text('1–25 of 28 packages'), findsOneWidget);
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows,
      hasLength(25),
    );
    await tester.ensureVisible(find.byTooltip('Next packages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next packages'));
    await tester.pumpAndSettle();
    expect(find.text('26–28 of 28 packages'), findsOneWidget);
    expect(find.text('package_27'), findsOneWidget);
    var table = tester.widget<DataTable>(find.byType(DataTable));
    table.columns[1].onSort!(1, false);
    await tester.pumpAndSettle();
    expect(find.text('1–25 of 28 packages'), findsOneWidget);
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(
      (table.rows.first.cells.first.child as GestureDetector).child,
      isA<Text>(),
    );
    expect(
      ((table.rows.first.cells.first.child as GestureDetector).child as Text)
          .data,
      'package_27',
    );
    final search = find.byKey(const Key('admin-queue-search-input'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'PACKAGE_27');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('1–1 of 1 packages'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(1));
    expect(find.text('package_27'), findsOneWidget);
    expect(find.text('package_00'), findsNothing);
    await tester.tap(find.byKey(const Key('admin-queue-clear-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-status-filter-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiple notices').last);
    await tester.pumpAndSettle();
    expect(find.text('1–1 of 1 packages'), findsOneWidget);
    expect(find.text('package_27'), findsOneWidget);
    expect(find.text('package_00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px at 3.2x keeps table keyboard access and full notices', (
    tester,
  ) async {
    const package = 'a_long_bundled_dependency_package';
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([package], fullNotice);
    });
    final semantics = tester.ensureSemantics();
    await mount(tester, width: 320, scale: 3.2);
    await tester.scrollUntilVisible(
      find.byType(AdminDataTable),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('admin-page-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminDataTable), findsOneWidget);
    final scroll = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scroll.thumbVisibility, isTrue);
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus &&
            widget.focusNode?.debugLabel == 'Admin table horizontal scrolling',
      ),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(scroll.controller!.offset, greaterThan(0));
    final open = find.byTooltip('Open $package');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(Table),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('admin-page-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.text(fullNotice), findsOneWidget);
    expect(find.text(package), findsOneWidget);
    final editableState = tester.state<EditableTextState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == fullNotice,
      ),
    );
    final RenderEditable renderedNotice = editableState.renderEditable;
    expect(renderedNotice.text!.toPlainText(), fullNotice);
    final finalCaret = renderedNotice.getLocalRectForCaret(
      const TextPosition(offset: fullNotice.length),
    );
    expect(
      finalCaret.bottom,
      lessThanOrEqualTo(renderedNotice.size.height + 1),
    );
    expect(
      find.bySemanticsLabel('Complete legal notices table, 1 notices'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'registry failure stays distinct from an empty license registry',
    (tester) async {
      var attempts = 0;
      LicenseRegistry.addLicense(() async* {
        if (attempts++ == 0) throw StateError('Synthetic registry failure');
        yield const LicenseEntryWithLineBreaks(['recovered'], fullNotice);
      });
      await mount(tester);
      expect(
        find.text('The bundled license notices could not be read.'),
        findsOneWidget,
      );
      expect(find.text('No bundled license notices'), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.text('Retry license loading'));
      await tester.pumpAndSettle();
      expect(find.text('recovered'), findsOneWidget);
      expect(find.text('1–1 of 1 packages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
