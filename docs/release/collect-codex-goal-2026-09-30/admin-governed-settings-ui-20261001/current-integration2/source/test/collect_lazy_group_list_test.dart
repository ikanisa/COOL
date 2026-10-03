import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpList(
  WidgetTester tester,
  Widget sliver, {
  ScrollController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: CustomScrollView(controller: controller, slivers: [sliver]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('large card lists build only the nearby rows', (tester) async {
    final built = <int>{};
    await pumpList(
      tester,
      CollectSliverCardList(
        itemCount: 1000,
        itemBuilder: (_, index) {
          built.add(index);
          return SizedBox(
            key: ValueKey(index),
            height: 72,
            child: Text('Row $index'),
          );
        },
      ),
    );
    expect(built, isNotEmpty);
    expect(built.length, lessThan(100));
    expect(find.text('Row 999'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'far scrolling builds later rows without constructing the full list',
    (tester) async {
      final built = <int>{};
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpList(
        tester,
        CollectSliverCardList(
          itemCount: 1000,
          itemBuilder: (_, index) {
            built.add(index);
            return SizedBox(
              key: ValueKey(index),
              height: 72,
              child: Text('Row $index'),
            );
          },
        ),
        controller: controller,
      );
      controller.jumpTo(10000);
      await tester.pumpAndSettle();
      expect(built.any((index) => index > 100), isTrue);
      expect(built.length, lessThan(1000));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'existing Activity callers retain flat decoration and normal padding defaults',
    () {
      final list = CollectSliverCardList(
        itemCount: 0,
        itemBuilder: (_, index) => const SizedBox(),
      );
      expect(list.emphasis, CollectCardEmphasis.flat);
      expect(list.padding, CollectSpacing.cardPadding);
    },
  );
  testWidgets('normal group-card tokens permit zero interior padding', (
    tester,
  ) async {
    await pumpList(
      tester,
      CollectSliverCardList(
        itemCount: 1,
        emphasis: CollectCardEmphasis.normal,
        padding: EdgeInsets.zero,
        itemBuilder: (_, index) =>
            const SizedBox(height: 72, child: Text('One group')),
      ),
    );
    final card = tester.widget<CollectSliverCardList>(
      find.byType(CollectSliverCardList),
    );
    expect(card.emphasis, CollectCardEmphasis.normal);
    expect(card.padding, EdgeInsets.zero);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a separator never follows the final row', (tester) async {
    await pumpList(
      tester,
      CollectSliverCardList(
        itemCount: 3,
        itemBuilder: (_, index) =>
            SizedBox(height: 48, child: Text('Row $index')),
        separatorBuilder: (_, index) => Text('Separator $index'),
      ),
    );
    expect(find.text('Separator 0'), findsOneWidget);
    expect(find.text('Separator 1'), findsOneWidget);
    expect(find.text('Separator 2'), findsNothing);
  });
  testWidgets('an empty GroupListSliver remains a valid sliver', (
    tester,
  ) async {
    await pumpList(
      tester,
      const GroupListSliver(collections: [], summaries: {}),
    );
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).slivers,
      contains(isA<GroupListSliver>()),
    );
    expect(tester.takeException(), isNull);
  });
}
