import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CollectCollection group() => CollectCollection(
  id: 'fixture-group',
  slug: 'fixture-group',
  creatorUserId: 'fixture-owner',
  title: 'Fixture group',
  description: 'Synthetic only',
  collectionType: CollectionType.ikimina,
  isPublic: true,
  createdAt: DateTime.utc(2026),
);
Future<void> pumpCard(
  WidgetTester tester,
  CollectionSummary? summary, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: GroupCard(collection: group(), summary: summary),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown editorial total and count stay unavailable', (
    tester,
  ) async {
    await pumpCard(tester, null);
    expect(find.text('—'), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Recorded contribution total unavailable',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Contributor count not available',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('measured zero remains zero', (tester) async {
    const summary = CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
    await pumpCard(tester, summary);
    expect(
      find.text(
        formatCurrencyTotals(summary.totalsByCurrency, separator: '\n'),
      ),
      findsOneWidget,
    );
    expect(find.text('—'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown count keeps known amount', (tester) async {
    const summary = CollectionSummary(
      amountRaisedRwf: 5000,
      supporterCount: null,
    );
    await pumpCard(tester, summary);
    expect(
      find.text(
        formatCurrencyTotals(summary.totalsByCurrency, separator: '\n'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('unavailable copy tolerates compact 2x text', (tester) async {
    await pumpCard(tester, null, scale: 2);
    expect(find.text('—'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('removed summary does not retain an earlier figure', (
    tester,
  ) async {
    const summary = CollectionSummary(amountRaisedRwf: 5000, supporterCount: 2);
    await pumpCard(tester, summary);
    await pumpCard(tester, null);
    expect(
      find.text(
        formatCurrencyTotals(summary.totalsByCurrency, separator: '\n'),
      ),
      findsNothing,
    );
  });
}
