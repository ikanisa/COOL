import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
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
  testWidgets('auth action announces and shows OTP submission progress', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AuthActionDock(
              embedded: true,
              otpSent: true,
              submitting: true,
              resendRemaining: 12,
              canSubmit: false,
              canResend: false,
              onSubmit: null,
              onAnotherNumber: null,
              onResend: null,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('auth_submit_progress')),
        findsOneWidget,
      );
      expect(find.text('Verifying code'), findsOneWidget);
      expect(find.bySemanticsLabel('Verifying code'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });

  test('MoMo launcher pre-fills the complete merchant USSD request', () {
    expect(
      momoUssdUri(receiverCode: '2209724', amountRwf: 100).toString(),
      'tel:*182**8*1*2209724*100%23',
    );
  });

  test('MoMo launcher normalizes the code and rejects unsafe input', () {
    expect(
      momoUssdUri(receiverCode: '220-9724', amountRwf: 6000).toString(),
      'tel:*182**8*1*2209724*6000%23',
    );
    expect(
      () => momoUssdUri(receiverCode: '123', amountRwf: 100),
      throwsFormatException,
    );
    expect(
      () => momoUssdUri(receiverCode: '2209724', amountRwf: 0),
      throwsFormatException,
    );
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
    expect(find.byType(BackdropFilter), findsNothing);

    final semantics = tester.ensureSemantics();
    expect(find.semantics.byLabel(RegExp(r'^Amount field$')), findsOne);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      find.semantics.byAction(SemanticsAction.setText),
      findsOne,
      reason:
          'Amount entry must expose one labeled editable semantics node without a duplicate inner field.',
    );

    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: 'Focused amount entry must not build an expensive blur layer.',
    );

    await tester.tap(find.text('10k'));
    expect(selectedAmount, 10000);
    semantics.dispose();
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
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.widget<Text>(find.text('Public building fund')).maxLines, 1);
    expect(find.text('Total collected'), findsNothing);
    expect(find.text('RWF 35,000'), findsOneWidget);
    expect(find.text('Members'), findsNothing);
  });

  testWidgets('visual group card keeps title compact without glass chrome', (
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

    expect(find.byType(BackdropFilter), findsNothing);
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

  testWidgets('group list panel renders a dense grouped money list', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final groups = [
        CollectCollection(
          id: 'church',
          slug: 'church',
          creatorUserId: 'u1',
          title: 'St Michel building fund',
          description: 'Community group',
          collectionType: CollectionType.church,
          createdAt: DateTime(2026),
        ),
        CollectCollection(
          id: 'sport',
          slug: 'sport',
          creatorUserId: 'u1',
          title: 'Kigali Lions away kit',
          description: 'Supporters group',
          collectionType: CollectionType.sport,
          createdAt: DateTime(2026),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: GroupListPanel(
                collections: groups,
                summaries: const {
                  'church': CollectionSummary(
                    amountRaisedRwf: 35000,
                    supporterCount: 2,
                  ),
                  'sport': CollectionSummary(
                    amountRaisedRwf: 12000,
                    supporterCount: 4,
                  ),
                },
                onGroupTap: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CollectCard), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('St Michel building fund'), findsOneWidget);
      expect(find.text('Church · 2 supporters'), findsOneWidget);
      expect(find.text('RWF 35,000'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Kigali Lions away kit, RWF 12,000, 4 supporters',
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('dense group list avoids a viewport-spanning backdrop filter', (
    tester,
  ) async {
    final groups = List<CollectCollection>.generate(
      12,
      (index) => CollectCollection(
        id: 'group-$index',
        slug: 'group-$index',
        creatorUserId: 'u1',
        title: 'Community group $index',
        description: 'Community group',
        createdAt: DateTime(2026),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: GroupListPanel(
              collections: groups,
              summaries: {
                for (final group in groups)
                  group.id: const CollectionSummary(
                    amountRaisedRwf: 35000,
                    supporterCount: 2,
                  ),
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CollectCard), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
    expect(find.text('Community group 11'), findsOneWidget);
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
    expect(find.text('Contribute with MoMo'), findsOneWidget);
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
