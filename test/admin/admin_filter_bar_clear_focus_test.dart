import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/admin/shared/components/admin_filter_bar.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _input = Key('admin-queue-search-input');
const _clear = Key('admin-queue-clear-search');
const _outside = Key('outside-search-focus');

class _SearchPage extends StatelessWidget {
  const _SearchPage({
    required this.controller,
    required this.outsideFocus,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final FocusNode outsideFocus;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminFilterBar(
              searchController: controller,
              searchLabel: 'Search recorded members',
              status: '',
              sortBy: 'created_at_desc',
              onStatusChanged: (_) {},
              onSortChanged: (_) {},
              onRefresh: onRefresh,
            ),
            TextButton(
              key: _outside,
              focusNode: outsideFocus,
              onPressed: outsideFocus.requestFocus,
              child: const Text('Move focus away'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _fillAndLeave(
  WidgetTester tester,
  TextEditingController controller,
  String query,
) async {
  await tester.tap(find.byKey(_input));
  await tester.enterText(find.byKey(_input), query);
  await tester.pumpAndSettle();
  expect(controller.text, query);
  expect(
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
    isTrue,
  );
  await tester.tap(find.byKey(_outside));
  await tester.pumpAndSettle();
  expect(
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
    isFalse,
    reason: 'Clear must handle a populated input that no longer owns focus.',
  );
}

void _compactViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 800);
}

void main() {
  testWidgets(
    'Clear refocuses an unfocused search with empty editing and semantics values exactly once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      final outsideFocus = FocusNode();
      final searches = <String>[];
      _compactViewport(tester);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AdminTheme.adapt(AppTheme.dark()),
            home: _SearchPage(
              controller: controller,
              outsideFocus: outsideFocus,
              onRefresh: () => searches.add(controller.text),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final searchFocus = tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode;
        for (final query in ['Recorded Member', 'Recorded Member again']) {
          final previousRefreshCount = searches.length;
          await _fillAndLeave(tester, controller, query);
          expect(
            tester
                .getSemantics(find.byType(EditableText))
                .getSemanticsData()
                .value,
            query,
          );
          final clear = find.byKey(_clear);
          expect(clear.hitTestable(), findsOneWidget);
          expect(
            tester.getSemantics(clear),
            isSemantics(
              label: 'Clear search',
              isButton: true,
              isEnabled: true,
              hasTapAction: true,
            ),
          );
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(searchFocus.hasFocus, isTrue);
          expect(
            tester.widget<EditableText>(find.byType(EditableText)).focusNode,
            same(searchFocus),
          );
          expect(tester.testTextInput.editingState?['text'], '');
          expect(
            tester
                .getSemantics(find.byType(EditableText))
                .getSemanticsData()
                .value,
            isEmpty,
          );
          expect(searches, hasLength(previousRefreshCount + 1));
          expect(searches.last, isEmpty);
          expect(find.byKey(_clear), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        controller.dispose();
        outsideFocus.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'Clear may refresh by immediately navigating and later reopen with a new owned focus node',
    (tester) async {
      final controller = TextEditingController();
      final outsideFocus = FocusNode();
      final navigator = GlobalKey<NavigatorState>();
      final searches = <String>[];
      var navigateOnRefresh = true;
      _compactViewport(tester);
      void refresh() {
        searches.add(controller.text);
        if (navigateOnRefresh) {
          navigator.currentState!.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Records overview')),
            ),
          );
        }
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AdminTheme.adapt(AppTheme.dark()),
            home: _SearchPage(
              controller: controller,
              outsideFocus: outsideFocus,
              onRefresh: refresh,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final originalFocus = tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode;
        await _fillAndLeave(tester, controller, 'Recorded Member');
        await tester.tap(find.byKey(_clear));
        await tester.pumpAndSettle();
        expect(searches, ['']);
        expect(controller.text, isEmpty);
        expect(find.byKey(_input), findsNothing);
        expect(find.text('Records overview'), findsOneWidget);
        expect(tester.takeException(), isNull);

        navigateOnRefresh = false;
        navigator.currentState!.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => _SearchPage(
              controller: controller,
              outsideFocus: outsideFocus,
              onRefresh: refresh,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final reopenedFocus = tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode;
        expect(reopenedFocus, isNot(same(originalFocus)));
        await _fillAndLeave(tester, controller, 'Reopened member search');
        await tester.tap(find.byKey(_clear));
        await tester.pumpAndSettle();
        expect(searches, ['', '']);
        expect(controller.text, isEmpty);
        expect(reopenedFocus.hasFocus, isTrue);
        expect(tester.testTextInput.editingState?['text'], '');
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        outsideFocus.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
