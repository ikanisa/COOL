import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/payments/payment_intent_status_screen.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/security/hash_utils.dart';
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

    expect(find.byIcon(Icons.public_rounded), findsWidgets);
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
    final cover = tester.widget<Image>(find.byType(Image));
    expect(
      (cover.image as AssetImage).assetName,
      'assets/brand/generated/collect_visual_momo_signal.png',
    );
    expect(find.text('Public'), findsNothing);
    expect(find.byIcon(CollectIcons.public), findsOneWidget);
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

  testWidgets('payment status screen renders receiver details', (tester) async {
    final repo = CollectRepository.fixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
        child: const MaterialApp(
          home: PaymentIntentStatusScreen(
            collectionId: 'col-church',
            intentId: 'intent-render',
          ),
        ),
      ),
    );

    expect(find.text('Waiting for MoMo SMS verification.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('St Michel treasury'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    expect(find.text('Status'), findsOneWidget);
    expect(
      find.textContaining(HashUtils.phoneHash('+250788123456')),
      findsNothing,
    );
    expect(find.text('Waiting for MoMo SMS'), findsNothing);
  });

  testWidgets('payment status screen tolerates 200 percent text scale', (
    tester,
  ) async {
    final repo = CollectRepository.fixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: PaymentIntentStatusScreen(
              collectionId: 'col-church',
              intentId: 'intent-render',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Waiting for MoMo SMS verification.'), findsOneWidget);
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

    await tester.tap(find.text('Review contribution'));
    await tester.pump();

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('Give to this church collection'), findsOneWidget);
    expect(find.text('Edit amount'), findsWidgets);
  });
}
