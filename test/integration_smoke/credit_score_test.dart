import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/credit/screens/credit_score_screen.dart';

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
      expect(find.text('Credit'), findsOneWidget);

      // Readiness checklist should render
      expect(find.text('Credit ready'), findsOneWidget);
      expect(find.text('Readiness checklist'), findsOneWidget);
      expect(find.text('Savings group'), findsOneWidget);
      expect(find.text('MoMo statements'), findsOneWidget);
      expect(find.text('You meet all requirements'), findsOneWidget);
    });

    testWidgets('shows not ready state when checklist is incomplete', (tester) async {
      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
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

      expect(find.text('Credit'), findsOneWidget);
      expect(find.text('Not ready yet'), findsOneWidget);
      expect(find.text('Join or create a savings group'), findsOneWidget);
      expect(find.text('Link your mobile money activity'), findsOneWidget);
    });
  });
}
