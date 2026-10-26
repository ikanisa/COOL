import 'package:collect_app/admin/shared/components/admin_filter_bar.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _statusKey = Key('admin-status-filter-select');
const _sortKey = Key('admin-sort-filter-select');
const _refreshKey = Key('admin-queue-refresh');

Widget _host({
  required TextEditingController controller,
  double scale = 1,
  VoidCallback? onRefresh,
  ValueChanged<String>? onStatus,
  List<AdminFilterOption>? statuses,
}) => MaterialApp(
  theme: AppTheme.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: AdminFilterBar(
        searchController: controller,
        status: '',
        sortBy: 'created_at_desc',
        onStatusChanged: onStatus ?? (_) {},
        onSortChanged: (_) {},
        onRefresh: onRefresh ?? () {},
        statusOptions:
            statuses ??
            const [
              AdminFilterOption(value: '', label: 'All'),
              AdminFilterOption(value: 'pending', label: 'Pending'),
            ],
      ),
    ),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('compact large-text search has its own full-width row', (
    tester,
  ) async {
    _size(tester, const Size(320, 568));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller, scale: 2));
    await tester.pumpAndSettle();
    final search = tester.getRect(find.byType(TextField));
    final status = tester.getRect(find.byKey(_statusKey));
    expect(search.width, greaterThanOrEqualTo(280));
    expect(status.top, greaterThanOrEqualTo(search.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal desktop search and controls remain on one row', (
    tester,
  ) async {
    _size(tester, const Size(800, 600));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller));
    await tester.pumpAndSettle();
    final search = tester.getRect(find.byType(TextField));
    final status = tester.getRect(find.byKey(_statusKey));
    expect((search.center.dy - status.center.dy).abs(), lessThan(2));
    expect(status.left, greaterThanOrEqualTo(search.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large desktop text reflows without clipping search', (
    tester,
  ) async {
    _size(tester, const Size(800, 600));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller, scale: 2));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(_statusKey)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(TextField)).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflow retains the native editor focus, value and selection', (
    tester,
  ) async {
    _size(tester, const Size(800, 600));
    final controller = TextEditingController(text: 'member 123');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    final before = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(before.hasFocus, isTrue);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    final after = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(identical(before, after), isTrue);
    expect(after.hasFocus, isTrue);
    expect(controller.text, 'member 123');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all three queue controls retain 48 logical-pixel targets', (
    tester,
  ) async {
    _size(tester, const Size(320, 568));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller, scale: 2));
    for (final key in [_statusKey, _sortKey, _refreshKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long popup option wraps and remains selectable', (
    tester,
  ) async {
    _size(tester, const Size(320, 568));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? selected;
    const longLabel = 'Requires a complete review of the payment allocation';
    await tester.pumpWidget(
      _host(
        controller: controller,
        scale: 2,
        onStatus: (value) => selected = value,
        statuses: const [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'needs_review', label: longLabel),
        ],
      ),
    );
    await tester.tap(find.byKey(_statusKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(longLabel));
    await tester.tap(find.text(longLabel));
    await tester.pumpAndSettle();
    expect(selected, 'needs_review');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing is not submission; the search keyboard action submits once',
    (tester) async {
      _size(tester, const Size(320, 568));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var refreshes = 0;
      await tester.pumpWidget(
        _host(controller: controller, onRefresh: () => refreshes++),
      );
      await tester.enterText(find.byType(TextField), 'receipt');
      expect(refreshes, 0);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(refreshes, 1);
    },
  );
}
