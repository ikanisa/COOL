import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reveal lazily built page content without dragging an overlapping action.
/// The target is still required: reaching the end cannot manufacture a match.
Future<void> revealCollectPageContent(
  WidgetTester tester,
  Finder target,
) async {
  final page = find
      .byWidgetPredicate(
        (widget) =>
            widget is ScrollView && widget.scrollDirection == Axis.vertical,
      )
      .first;
  final scrollable = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
    position.jumpTo(
      (position.pixels + 160).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }
  expect(
    target,
    findsWidgets,
    reason:
        'Required page content after bounded scroll; '
        'position ${position.pixels}/${position.maxScrollExtent}; '
        'visible text ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(" | ")}',
  );
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}
