import 'package:collect_app/admin/shared/components/admin_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _input = Key('admin-queue-search-input');
const _clear = Key('admin-queue-clear-search');
const _apply = Key('admin-queue-apply-search');

Future<void> _pumpFilterBar(
  WidgetTester tester, {
  required TextEditingController controller,
  required VoidCallback onRefresh,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminFilterBar(
          searchController: controller,
          searchLabel: 'Search groups',
          status: '',
          sortBy: 'created_at_desc',
          onStatusChanged: (_) {},
          onSortChanged: (_) {},
          onRefresh: onRefresh,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search input and suffix actions have independent semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final controller = TextEditingController(text: 'private');
      addTearDown(controller.dispose);
      await _pumpFilterBar(tester, controller: controller, onRefresh: () {});

      final input = find.semantics.byPredicate(
        (node) => node.getSemanticsData().flagsCollection.isTextField,
      );
      expect(input, findsOne);
      expect(input.evaluate().single.label, contains('Search groups'));
      expect(
        input.evaluate().single,
        isSemantics(
          value: 'private',
          hint: 'Searches all matching records. Press Enter or Apply search.',
          isTextField: true,
        ),
      );
      for (final label in ['Clear search', 'Apply search']) {
        final button = find.semantics.byLabel(label);
        expect(button, findsOne);
        expect(
          button.evaluate().single,
          isSemantics(
            label: label,
            tooltip: '',
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Tab reaches named Clear and Apply actions with correct behavior',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = TextEditingController(text: 'private');
        addTearDown(controller.dispose);
        final searches = <String>[];
        await _pumpFilterBar(
          tester,
          controller: controller,
          onRefresh: () => searches.add(controller.text),
        );

        await tester.tap(find.byKey(_input));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(find.byKey(_clear)),
          isSemantics(label: 'Clear search', isButton: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(find.byKey(_apply)),
          isSemantics(label: 'Apply search', isButton: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(searches, ['private']);
        expect(controller.text, 'private');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          tester.getSemantics(find.byKey(_clear)),
          isSemantics(label: 'Clear search', isButton: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(searches, ['private', '']);
        expect(controller.text, isEmpty);
        expect(find.byKey(_clear), findsNothing);
        expect(find.semantics.byLabel('Apply search'), findsOne);

        await tester.enterText(find.byKey(_input), 'active groups');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(searches, ['private', '', 'active groups']);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
