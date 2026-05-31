import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark Collect color tokens resolve', () {
    final light = AppTheme.light().extension<CollectColors>();
    final dark = AppTheme.dark().extension<CollectColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.surface.computeLuminance(), greaterThan(0.2));
    expect(dark!.surface.computeLuminance(), lessThan(0.2));
  });

  test('RWF amount typography uses tabular numerals', () {
    final style = CollectTypography.amountHero(CollectColors.light.textPrimary);

    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('button, card, and status chip expose labels', (tester) async {
    await _pumpCollect(
      tester,
      CollectCard(
        child: Column(
          children: [
            CollectButton(label: 'Continue safely', onPressed: () {}),
            const CollectStatusChip(
              label: 'Needs review',
              tone: CollectStatusTone.warning,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Continue safely'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(CollectStatusChip)),
      matchesSemantics(label: 'Status: Needs review'),
    );
  });

  testWidgets('payment intent status card keeps SMS-first boundary visible', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const PaymentIntentStatusCard(
        amountRwf: 5000,
        receiverLabel: 'St Michel treasury',
        receiverMomoNumber: '+250788123456',
        memberLabel: 'Collect ID 038491',
        network: 'MTN MOMO',
        status: 'pending',
      ),
    );

    expect(find.text('RWF 5,000'), findsOneWidget);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('Collect ID 038491'), findsOneWidget);
    expect(find.textContaining('Collect waits for SMS'), findsOneWidget);
    expect(find.textContaining('Do not paste SMS'), findsOneWidget);
    expect(find.textContaining('Code'), findsNothing);
  });

  testWidgets('receiver consent card shows SMS access privacy copy', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      ReceiverConsentCard(
        flagsEnabled: true,
        consented: false,
        isSyncing: false,
        onConsentChanged: (_) {},
        onSync: () {},
      ),
    );

    expect(find.text('Receiver consent'), findsOneWidget);
    expect(find.text('Consent required'), findsOneWidget);
    expect(find.text('Sync consented SMS'), findsOneWidget);
    expect(find.textContaining('Raw SMS is never public'), findsOneWidget);
  });

  testWidgets('ledger row renders tabular transaction details', (tester) async {
    await _pumpCollect(
      tester,
      LedgerRow.confirmed(
        contribution: Contribution(
          id: 'con-1',
          collectionId: 'col-1',
          amountRwf: 15000,
          supporterLabel: 'Collect ID 038491',
          createdAt: DateTime(2026),
          transactionId: 'MTN-001',
        ),
      ),
    );

    expect(find.text('Collect ID 038491'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsOneWidget);
    expect(find.text('MTN-001'), findsOneWidget);
  });

  testWidgets('empty, error, and loading states render', (tester) async {
    await _pumpCollect(
      tester,
      const Column(
        children: [
          Expanded(
            child: CollectEmptyState(
              icon: CollectIcons.collections,
              title: 'No groups yet',
              message: 'Create an SMS-first MoMo group.',
            ),
          ),
          Expanded(
            child: CollectErrorState(
              title: 'Could not load',
              message: 'Try again when the connection is stable.',
            ),
          ),
          LoadingSkeleton(lines: 2),
        ],
      ),
    );

    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.text('Could not load'), findsOneWidget);
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  test('primary route smoke list keeps admin out of member app', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/home',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId',
        '/dev/design-system',
      ]),
    );
    expect(collectRoutePaths, isNot(contains('/admin')));
  });
}

Future<void> _pumpCollect(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
