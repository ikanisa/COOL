import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/payments/payment_intent_status_screen.dart';
import 'package:collect_app/core/security/hash_utils.dart';
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

  testWidgets('group card tolerates long names and large verified totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CollectionCard(
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
    expect(find.text('128 members'), findsOneWidget);
  });

  testWidgets('payment status screen renders receiver details', (tester) async {
    final repo = CollectRepository.seeded();
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

    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsWidgets);
    expect(find.text('Payment'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    expect(find.text('View pending details'), findsOneWidget);
    expect(
      find.textContaining(HashUtils.phoneHash('+250788123456')),
      findsNothing,
    );
    expect(find.text('Waiting for MoMo SMS'), findsNothing);
  });
}
