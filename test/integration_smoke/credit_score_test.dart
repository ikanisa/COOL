
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/credit/screens/credit_score_screen.dart';
import 'package:cool_app/features/credit/models/credit_insights.dart';
import 'package:cool_app/features/credit/providers/credit_insights_provider.dart';

import 'test_harness.dart';

void main() {
  group('Credit score smoke', () {
    testWidgets('renders readiness checklist with mock data', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          creditInsightsProvider.overrideWith(
            (ref) => Future.value(
              const CreditInsights(
                creditReadiness: 'Excellent',
                estimatedScoreRange: '750 - 800',
                savingsDisciplineScore: 85,
                incomeStabilityScore: 90,
                spendingAnalysis: 'Healthy spending habits detected.',
                keyStrengths: ['Consistent savings', 'Low debt-to-income'],
                improvementAreas: ['Diverse credit mix needed'],
                proactiveTips: ['Consider a credit card for mix'],
              ),
            ),
          ),
          groupsListProvider.overrideWith((ref) => [
            const Group(
              id: 'g1',
              creatorId: 'u1',
              name: 'Test Group',
              type: 'saving',
              visibility: 'public',
              amount: 10000,
              targetAmount: 50000,
              memberCount: 5,
              country: 'RW',
              frequency: 'monthly',
            ),
          ]),
          momoStatementBundleProvider(const MomoStatementQuery()).overrideWith(
            (ref) => Future.value(
              MomoStatementBundle(
                walletEntries: [
                  MomoWalletEntry(
                    id: 'e1',
                    amount: 5000,
                    entryType: 'credit',
                    ledgerStatus: 'confirmed',
                    occurredAt: DateTime.parse('2026-03-12T10:00:00Z'),
                    currency: 'RWF',
                    txCategory: 'transfer',
                    cashflowBucket: 'wallet',
                    label: 'Transfer',
                  ),
                ],
                savingsEntries: [],
                walletTotalCount: 1,
                savingsTotalCount: 0,
              ),
            ),
          ),
        ],
      );

      await settleTestApp(tester);

      // The screen title should be present
      expect(find.text('Credit Agent'), findsOneWidget);

      // AI Insights should render
      expect(find.text('Credit Readiness'), findsOneWidget);
      expect(find.text('Spending analysis'), findsOneWidget);
      expect(find.text('Proactive coaching'), findsOneWidget);
      expect(find.text('Official Bank Report'), findsOneWidget);
    });

    testWidgets('shows not ready state when checklist is incomplete', (tester) async {
      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          creditInsightsProvider.overrideWith(
            (ref) => Future.value(
              const CreditInsights(
                creditReadiness: 'Building',
                estimatedScoreRange: '300 - 400',
                savingsDisciplineScore: 10,
                incomeStabilityScore: 20,
                spendingAnalysis: 'More data needed.',
                keyStrengths: [],
                improvementAreas: ['Inconsistent savings'],
                proactiveTips: ['Join a savings group'],
              ),
            ),
          ),
          groupsListProvider.overrideWith((ref) => []),
          momoStatementBundleProvider(const MomoStatementQuery()).overrideWith(
            (ref) => Future.value(
              const MomoStatementBundle(
                walletEntries: [],
                savingsEntries: [],
              ),
            ),
          ),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Credit Agent'), findsOneWidget);
      expect(find.text('Spending analysis'), findsOneWidget);
    });
  });
}
