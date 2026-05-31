import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/payments/payment_intent_status_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collection_card.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MoMo launcher uses USSD menu, not receiver phone call', () {
    expect(momoUssdUri().toString(), 'tel:*182%23');
  });

  test('activity labels use compact Collect IDs', () {
    expect(compactCollectIdLabel('Collect ID 038491'), '#038491');
    expect(compactCollectIdLabel('Collect member'), 'Collect member');
  });

  testWidgets('group card renders SMS-first details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionCard(
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
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('Help'), findsNothing);
    expect(find.text('Auto'), findsNothing);
  });

  testWidgets('payment status screen renders receiver details', (tester) async {
    final repo = CollectRepository.seeded();
    final intent = await repo.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
        child: MaterialApp(
          home: PaymentIntentStatusScreen(
            collectionId: 'col-church',
            intentId: intent.id,
          ),
        ),
      ),
    );

    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('Waiting for MoMo SMS'), findsNothing);
    expect(find.text('Payment'), findsWidgets);
  });
}
