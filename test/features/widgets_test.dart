import 'package:collect_app/features/payments/payment_instructions_screen.dart';
import 'package:collect_app/features/receiver_sms/receiver_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collection_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collection card renders finance details', (tester) async {
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
              category: 'Medical support',
              targetAmountRwf: 100000,
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
    expect(find.textContaining('25%'), findsOneWidget);
  });

  testWidgets('receiver mode consent screen renders privacy copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ReceiverScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Raw SMS is never public'), findsOneWidget);
  });

  testWidgets('payment instructions screen renders receiver details', (
    tester,
  ) async {
    final repo = CollectRepository.seeded();
    final intent = await repo.createPaymentIntent(
      const PaymentIntentDraft(
        collectionId: 'col-church',
        amountRwf: 5000,
        anonymityChoice: 'anonymous',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
        child: MaterialApp(
          home: PaymentInstructionsScreen(
            collectionId: 'col-church',
            intentId: intent.id,
          ),
        ),
      ),
    );

    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.textContaining('Mobile money USSD'), findsOneWidget);
    expect(find.textContaining('Collect does not move money'), findsOneWidget);
  });
}
