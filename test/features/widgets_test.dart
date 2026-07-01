import 'dart:io';

import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/date_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MoMo launcher uses USSD menu, not receiver phone call', () {
    expect(momoUssdUri().toString(), 'tel:*182%23');
  });

  test('activity labels use compact Collect IDs', () {
    expect(compactCollectIdLabel('Collect ID 038491'), '038491');
    expect(compactCollectIdLabel('Collect member'), 'Collect member');
  });

  testWidgets('amount entry panel compacts quick amounts and emits selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: '5000');
    addTearDown(controller.dispose);
    var selectedAmount = 5000;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmountEntryPanel(
            controller: controller,
            amount: selectedAmount,
            quickAmounts: const [5000, 10000, 1000000],
            onQuickAmount: (amount) => selectedAmount = amount,
            detail: 'Choose a contribution amount.',
          ),
        ),
      ),
    );

    expect(find.text('5k'), findsOneWidget);
    expect(find.text('10k'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('RWF'), findsOneWidget);

    await tester.tap(find.text('10k'));
    expect(selectedAmount, 10000);
  });

  testWidgets('group card renders SMS-first details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionSummaryCard(
            collection: CollectCollection(
              id: 'c1',
              slug: 'medical',
              creatorUserId: 'u1',
              title: 'Medical support',
              description: 'Help',
              createdAt: DateTime(2026),
            ),
            summary: const CollectionSummary(
              amountRaisedRwf: 25000,
              supporterCount: 3,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Medical support'), findsWidgets);
    expect(find.text('Members'), findsNothing);
    expect(find.byIcon(CollectIcons.people), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Help'), findsNothing);
    expect(find.text('Auto'), findsNothing);
  });

  testWidgets('group card tolerates long names and large verified totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CollectionSummaryCard(
              collection: CollectCollection(
                id: 'c-long',
                slug: 'st-michel-medical-support',
                creatorUserId: 'u1',
                title: 'St Michel emergency medical support group',
                description: 'Private group',
                createdAt: DateTime(2026),
              ),
              summary: const CollectionSummary(
                amountRaisedRwf: 12500000,
                supporterCount: 128,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('St Michel emergency medical support group'),
      findsOneWidget,
    );
    expect(find.text('RWF 12,500,000'), findsOneWidget);
    expect(find.text('Members'), findsNothing);
    expect(find.byIcon(CollectIcons.people), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('public discovery group card uses public icon, not lock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 284,
            height: 224,
            child: GroupCard(
              collection: CollectCollection(
                id: 'public-card',
                slug: 'public-card',
                creatorUserId: 'u1',
                title: 'Public building fund',
                description: 'Public group',
                createdAt: DateTime(2026),
              ),
              summary: const CollectionSummary(
                amountRaisedRwf: 35000,
                supporterCount: 2,
              ),
              variant: GroupCardVariant.publicDiscovery,
            ),
          ),
        ),
      ),
    );

    expect(
      _readGroupCardLibrary(),
      contains("CollectSemanticIcons.forKeyword('public')"),
    );
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.widget<Text>(find.text('Public building fund')).maxLines, 1);
    expect(find.text('Total collected'), findsNothing);
    expect(find.text('RWF 35,000'), findsOneWidget);
    expect(find.text('Members'), findsNothing);
  });

  testWidgets('visual group card keeps title compact with glass chrome', (
    tester,
  ) async {
    const title = 'St Michel building fund with a longer community name';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 260,
            child: GroupCard(
              collection: CollectCollection(
                id: 'visual-card',
                slug: 'visual-card',
                creatorUserId: 'u1',
                title: title,
                description: 'Owner group',
                isPublic: true,
                createdAt: DateTime(2026),
              ),
              summary: const CollectionSummary(
                amountRaisedRwf: 35000,
                supporterCount: 2,
              ),
              variant: GroupCardVariant.visual,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Public'), findsNothing);
    expect(
      _readGroupCardLibrary(),
      contains("CollectSemanticIcons.forKeyword('public')"),
    );
    expect(tester.widget<Text>(find.text(title)).maxLines, 1);
    expect(
      tester.widget<Text>(find.text(title)).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('owned group card uses protected shield, not lock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: GroupCard(
              collection: CollectCollection(
                id: 'owned-card',
                slug: 'owned-card',
                creatorUserId: 'u1',
                title: 'Owned building fund',
                description: 'Receiver protected',
                createdAt: DateTime(2026),
              ),
              summary: const CollectionSummary(
                amountRaisedRwf: 35000,
                supporterCount: 2,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  test('Collect date formatter keeps activity timestamps compact', () {
    expect(
      formatCollectDateTime(DateTime.utc(2026, 6, 3, 9, 45)),
      contains('2026'),
    );
    expect(
      formatCollectDateTime(DateTime.utc(2026, 6, 3, 9, 45)),
      isNot(contains('.')),
    );
  });

  testWidgets('contribution flow keeps primary action pinned', (tester) async {
    final repo = CollectRepository.fixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ContributionFlowScreen(collectionId: 'col-church'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Target account'), findsNothing);
    expect(find.text('Review contribution'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '6000');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Review contribution'));
    await tester.pumpAndSettle();

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('Pay with MOMO'), findsOneWidget);
    expect(find.text('Edit amount'), findsWidgets);
  });
}

String _readGroupCardLibrary() {
  return [
    'lib/shared/widgets/collect_group_cards.dart',
    'lib/shared/widgets/collect_group_card_media.dart',
    'lib/shared/widgets/collect_group_card_metrics.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}
