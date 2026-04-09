import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/momo/screens/momo_statements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../integration_smoke/test_harness.dart';
import 'momo_statements_test_support.dart';

void main() {
  testWidgets('direct Mobile Money entry can return home', (tester) async {
    final repository = FakeMomoStatementRepository(const MomoStatementBundle());
    final container = createMomoStatementsTestContainer(repository: repository);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Home'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpMomoStatementsRouterApp(
      tester,
      container: container,
      router: router,
    );

    await tester.tap(find.byTooltip('Back'));
    await settleTestApp(tester);

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Open on Mobile Money pushes statements screen', (tester) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-1',
            entryType: 'credit',
            ledgerStatus: 'posted',
            amount: 25000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 11, 9, 30),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Cash in',
            counterpartyName: 'MTN Rwanda',
            reference: 'MM-123',
          ),
        ],
        savingsEntries: [
          SavingsStatementEntry(
            id: 'savings-1',
            groupId: 'group-1',
            groupName: 'Western Builders Pool',
            amount: 15000,
            status: 'confirmed',
            createdAt: DateTime(2026, 3, 10),
            reference: 'GCT-123',
          ),
        ],
        walletTotalCount: 1,
        savingsTotalCount: 1,
      ),
    );
    final container = createMomoStatementsTestContainer(repository: repository);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
        GoRoute(
          path: '/momo/statements',
          builder: (context, state) => const MomoStatementsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpMomoStatementsRouterApp(
      tester,
      container: container,
      router: router,
    );

    router.go('/momo/statements');
    await tester.pump();
    await settleTestApp(tester);

    expect(find.byType(MomoStatementsScreen), findsOneWidget);
  });

  testWidgets('wallet statements load the draft ledger summary', (tester) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-draft-1',
            entryType: 'credit',
            ledgerStatus: 'draft',
            amount: 500,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 7, 13, 53),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Received 500 RWF from Jean Bosco',
            counterpartyName: 'Jean Bosco AHORUKOMEYE',
            reference: '26547384890',
            description: 'Recovered from SMS inbox on device.',
          ),
        ],
        walletTotalCount: 1,
      ),
    );
    final container = createMomoStatementsTestContainer(repository: repository);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
        GoRoute(
          path: '/momo/statements',
          builder: (context, state) => const MomoStatementsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpMomoStatementsRouterApp(
      tester,
      container: container,
      router: router,
    );

    router.go('/momo/statements');
    await tester.pump();
    await settleTestApp(tester);

    expect(find.textContaining('Jean Bosco'), findsWidgets);
    expect(find.text('Wallet ledger'), findsOneWidget);
    expect(find.text('1/1 shown'), findsOneWidget);
  });

  testWidgets(
    'tapping the statements card body also pushes statements screen',
    (tester) async {
      final repository = FakeMomoStatementRepository(
        const MomoStatementBundle(),
      );
      final container = createMomoStatementsTestContainer(
        repository: repository,
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
          GoRoute(
            path: '/momo/statements',
            builder: (context, state) => const MomoStatementsScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await pumpMomoStatementsRouterApp(
        tester,
        container: container,
        router: router,
      );

      router.go('/momo/statements');
      await tester.pump();
      await settleTestApp(tester);

      expect(find.byType(MomoStatementsScreen), findsOneWidget);
      expect(find.byType(MomoStatementsScreen), findsOneWidget);
    },
  );
}
