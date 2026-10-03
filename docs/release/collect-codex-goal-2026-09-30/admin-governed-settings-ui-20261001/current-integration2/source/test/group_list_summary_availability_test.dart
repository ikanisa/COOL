import 'dart:ui' show SemanticsAction;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixture-only identities; no live repository or payment service is used.
CollectCollection _group(String id) => CollectCollection(
  id: id,
  slug: id,
  creatorUserId: 'summary-test-owner',
  title: 'Group $id',
  description: 'Summary availability fixture',
  createdAt: DateTime.utc(2026, 9, 26),
);

String _amount(CollectionSummary summary) =>
    formatCurrencyTotals(summary.totalsByCurrency, separator: '\n');

String _missingLabel(CollectCollection group) =>
    '${group.title}, Group total unavailable, Contributor count unavailable';

Future<void> _pumpGroups(
  WidgetTester tester, {
  required bool lazy,
  required List<CollectCollection> groups,
  required Map<String, CollectionSummary> summaries,
  ValueChanged<CollectCollection>? onTap,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: lazy
            ? CustomScrollView(
                slivers: [
                  GroupListSliver(
                    collections: groups,
                    summaries: summaries,
                    onGroupTap: onTap,
                  ),
                ],
              )
            : SingleChildScrollView(
                child: GroupListPanel(
                  collections: groups,
                  summaries: summaries,
                  onGroupTap: onTap,
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final lazy in [false, true]) {
    group(lazy ? 'Lazy group summaries' : 'Panel group summaries', () {
      testWidgets('missing summary never fabricates zero values', (
        tester,
      ) async {
        final group = _group('missing');
        const zero = CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: const {},
        );
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(find.text(_amount(zero)), findsNothing);
        expect(find.text('0'), findsNothing);
        expect(find.bySemanticsLabel(_missingLabel(group)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a reported zero remains zero', (tester) async {
        final group = _group('zero');
        const summary = CollectionSummary(
          amountRaisedRwf: 0,
          supporterCount: 0,
        );
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: {group.id: summary},
        );
        expect(find.text(_amount(summary)), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('Not available'), findsNothing);
      });

      testWidgets('reported amount and contributor count retain formatting', (
        tester,
      ) async {
        final group = _group('known');
        const summary = CollectionSummary(
          amountRaisedRwf: 125000,
          supporterCount: 12,
        );
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: {group.id: summary},
        );
        expect(find.text(_amount(summary)), findsOneWidget);
        expect(find.text(summary.supporterCountLabel), findsOneWidget);
        expect(find.text('Not available'), findsNothing);
      });

      testWidgets('unknown count does not suppress a known amount', (
        tester,
      ) async {
        final group = _group('count-unknown');
        const summary = CollectionSummary(
          amountRaisedRwf: 7000,
          supporterCount: null,
        );
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: {group.id: summary},
        );
        expect(find.text(_amount(summary)), findsOneWidget);
        expect(find.text(summary.supporterCountLabel), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            '${group.title}, ${_amount(summary)}, ${summary.supporterCountSemantics}',
          ),
          findsOneWidget,
        );
        expect(find.text('0'), findsNothing);
      });

      testWidgets('arrival and removal of a summary refresh its availability', (
        tester,
      ) async {
        final group = _group('changing');
        const summary = CollectionSummary(
          amountRaisedRwf: 5000,
          supporterCount: 3,
        );
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: const {},
        );
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: {group.id: summary},
        );
        expect(find.text(_amount(summary)), findsOneWidget);
        expect(find.text('Not available'), findsNothing);
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: const {},
        );
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(find.text(_amount(summary)), findsNothing);
      });

      testWidgets('a missing row does not alter a neighboring known row', (
        tester,
      ) async {
        final known = _group('known-neighbor');
        final missing = _group('missing-neighbor');
        const summary = CollectionSummary(
          amountRaisedRwf: 9000,
          supporterCount: 4,
        );
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [known, missing],
          summaries: {known.id: summary},
        );
        expect(find.text(_amount(summary)), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a missing summary leaves the group action available', (
        tester,
      ) async {
        final group = _group('navigable');
        CollectCollection? selected;
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: const {},
          onTap: (value) => selected = value,
        );
        final data = tester
            .getSemantics(find.bySemanticsLabel(_missingLabel(group)))
            .getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(find.text(group.title));
        await tester.pump();
        expect(selected, same(group));
      });

      testWidgets('a read-only row does not advertise a tap action', (
        tester,
      ) async {
        final group = _group('read-only');
        await _pumpGroups(
          tester,
          lazy: lazy,
          groups: [group],
          summaries: const {},
        );
        final data = tester
            .getSemantics(find.bySemanticsLabel(_missingLabel(group)))
            .getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isFalse);
      });

      for (final scale in [2.0, 3.0]) {
        testWidgets('availability text wraps at 320px and ${scale}x text', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _pumpGroups(
            tester,
            lazy: lazy,
            groups: [_group('large-text')],
            summaries: const {},
            textScale: scale,
          );
          expect(find.text('Not available'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}
