import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/momo/screens/momo_statements_screen.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../integration_smoke/test_harness.dart';
import 'momo_statements_test_support.dart';

void main() {
  testWidgets('wallet filters and PDF export use the visible payer view', (
    tester,
  ) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-alice',
            entryType: 'credit',
            ledgerStatus: 'posted',
            amount: 25000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 11, 9, 30),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Alice transfer',
            counterpartyName: 'Alice',
            reference: 'MM-123',
          ),
          MomoWalletEntry(
            id: 'wallet-bob',
            entryType: 'debit',
            ledgerStatus: 'posted',
            amount: 9000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 10, 9, 30),
            txCategory: 'cash_out',
            cashflowBucket: 'expense',
            label: 'Bob payout',
            counterpartyName: 'Bob',
            reference: 'MM-456',
          ),
        ],
        walletTotalCount: 2,
      ),
    );
    final exportService = FakeStatementExportService();
    final downloadService = FakeStatementDownloadService();
    final container = createMomoStatementsTestContainer(
      repository: repository,
      exportService: exportService,
      downloadService: downloadService,
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

    final optionsButton = find.byKey(
      const ValueKey<String>('statement-open-options'),
    );
    await tester.ensureVisible(optionsButton);
    await tester.tap(optionsButton);
    await settleTestApp(tester);

    final payerField = find.byKey(
      const ValueKey<String>('statement-party-filter'),
    );
    await tester.ensureVisible(payerField);
    await tester.tap(payerField, warnIfMissed: false);
    await settleTestApp(tester);
    await tester.tap(find.text('Alice').last);
    await settleTestApp(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('statement-apply-filters')),
    );
    await settleTestApp(tester);

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob payout'), findsNothing);

    await tester.tap(optionsButton);
    await settleTestApp(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('statement-export-pdf')),
    );
    await settleTestApp(tester);

    expect(exportService.walletExportCalls, 1);
    expect(downloadService.lastExport, isNotNull);
    expect(exportService.lastFormat, StatementExportFormat.pdf);
    expect(exportService.lastWalletEntries.map((entry) => entry.id), <String>[
      'wallet-alice',
    ]);
    expect(exportService.lastMetadata?.filterLabel, contains('Payer: Alice'));
  });

  testWidgets('day filter updates the statement query window', (tester) async {
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
        walletTotalCount: 1,
      ),
    );
    final container = createMomoStatementsTestContainer(repository: repository);

    await pumpMomoStatementsHomeApp(tester, container: container);

    Future<MomoStatementQuery> waitForLatestQuery({
      required int minimumCount,
    }) async {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (repository.queries.length >= minimumCount) {
          return repository.queries.last;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      throw StateError('Expected at least $minimumCount statement queries.');
    }

    final initialQuery = await waitForLatestQuery(minimumCount: 1);
    expect(initialQuery.startDate, isNotNull);
    expect(initialQuery.endDate, isNotNull);

    await settleTestApp(tester);

    final periodSelector = find.byKey(
      const ValueKey<String>('statement-period-selector'),
    );
    expect(periodSelector, findsOneWidget);
    await tester.ensureVisible(periodSelector);
    await tester.tap(periodSelector);
    await settleTestApp(tester);
    await tester.tap(find.text('Day').last);
    await settleTestApp(tester);

    final dayQuery = await waitForLatestQuery(minimumCount: 2);
    final today = DateUtils.dateOnly(DateTime.now());
    expect(dayQuery.startDate, today);
    expect(dayQuery.endDate, today);

    await tester.tap(periodSelector);
    await settleTestApp(tester);
    await tester.tap(find.text('All time').last);
    await settleTestApp(tester);

    final allQuery = await waitForLatestQuery(minimumCount: 3);
    expect(allQuery.startDate, isNull);
    expect(allQuery.endDate, isNull);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
