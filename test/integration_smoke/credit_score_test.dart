import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/providers/credit_provider.dart';
import 'package:cool_app/features/credit/repositories/credit_repository.dart';
import 'package:cool_app/features/credit/screens/credit_score_screen.dart';

import 'test_harness.dart';

class MockCreditRepository extends Mock implements CreditRepository {}

void main() {
  group('Credit score smoke', () {
    testWidgets('renders score ring and factor cards with mock data', (
      tester,
    ) async {
      final repository = MockCreditRepository();
      final dashboard = CreditDashboard(
        statementCount: 24,
        groupContributionCount: 6,
        activeMonthCount: 8,
        score: 720,
        scoreVersion: 'v2',
        scoreBand: 'good',
        summary:
            'Strong transaction history. Consistent group savings improve your profile.',
        creditEntryCount: 120,
        debitEntryCount: 90,
        creditTotal: 2500000,
        debitTotal: 1800000,
        groupTotal: 360000,
        averageGroupContribution: 5000,
        factors: const <CreditFactor>[
          CreditFactor(
            key: 'tx_volume',
            label: 'Transaction Volume',
            icon: Icons.payments_rounded,
            score: 85,
          ),
          CreditFactor(
            key: 'group_save',
            label: 'Group Savings',
            icon: Icons.savings_rounded,
            score: 72,
          ),
        ],
      );

      when(
        () => repository.loadDashboard(any()),
      ).thenAnswer((_) async => dashboard);

      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          creditRepositoryProvider.overrideWithValue(repository),
        ],
      );

      // The screen title should be present
      expect(find.text('Credit'), findsOneWidget);

      // Score band should render
      expect(find.textContaining('Good Standing'), findsWidgets);

      // Factor cards should render
      expect(find.text('Transaction Volume'), findsOneWidget);
      expect(find.text('Group Savings'), findsOneWidget);
    });

    testWidgets('shows empty state when no report exists', (tester) async {
      final repository = MockCreditRepository();
      const dashboard = CreditDashboard(statementCount: 0);

      when(
        () => repository.loadDashboard(any()),
      ).thenAnswer((_) async => dashboard);

      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          creditRepositoryProvider.overrideWithValue(repository),
        ],
      );

      expect(find.text('Credit'), findsOneWidget);
      // No score ring expected — we just verify it doesn't crash
    });

    testWidgets('shows loading state when dashboard takes time', (
      tester,
    ) async {
      final repository = MockCreditRepository();

      when(
        () => repository.loadDashboard(any()),
      ).thenAnswer((_) => Completer<CreditDashboard>().future);

      await pumpScopedApp(
        tester,
        child: const CreditScoreScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          creditRepositoryProvider.overrideWithValue(repository),
        ],
      );

      // Should have loading indicator or skeletons, not crash
      expect(find.text('Credit'), findsOneWidget);
    });
  });
}
