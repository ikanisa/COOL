import 'package:cool_app/features/home/repositories/home_dashboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildHomeRecentTransactions', () {
    test('includes wallet ledger rows even without group memberships', () {
      final transactions = buildHomeRecentTransactions(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'entry_type': 'credit',
            'ledger_status': 'draft',
            'amount': 500,
            'currency': 'RWF',
            'tx_datetime': '2026-03-07T13:53:00Z',
            'statement_label': 'Received 500 RWF from Jean Bosco AHORUKOMEYE.',
          },
        ],
        groupsById: const <String, String>{},
      );

      expect(transactions, hasLength(1));
      expect(
        transactions.single.title,
        equals('Received 500 RWF from Jean Bosco AHORUKOMEYE.'),
      );
      expect(transactions.single.type, equals('credit'));
      expect(transactions.single.amount, equals(500));
      expect(transactions.single.status, equals('draft'));
    });
  });

  group('calculateHomeMonthlyNetChange', () {
    test(
      'counts confirmed contributions and wallet cashflow for the month',
      () {
        final monthlyNet = calculateHomeMonthlyNetChange(
          contributionRows: <Map<String, dynamic>>[
            <String, dynamic>{
              'amount': 1000,
              'status': 'confirmed',
              'created_at': '2026-03-02T08:00:00Z',
            },
            <String, dynamic>{
              'amount': 2000,
              'status': 'pending',
              'created_at': '2026-03-03T08:00:00Z',
            },
            <String, dynamic>{
              'amount': 300,
              'status': 'confirmed',
              'created_at': '2026-02-20T08:00:00Z',
            },
          ],
          walletRows: <Map<String, dynamic>>[
            <String, dynamic>{
              'entry_type': 'credit',
              'amount': 500,
              'tx_datetime': '2026-03-04T09:00:00Z',
            },
            <String, dynamic>{
              'entry_type': 'debit',
              'amount': 200,
              'tx_datetime': '2026-03-05T09:00:00Z',
            },
            <String, dynamic>{
              'entry_type': 'credit',
              'amount': 999,
              'tx_datetime': '2026-02-28T09:00:00Z',
            },
          ],
          now: DateTime.utc(2026, 3, 12),
        );

        expect(monthlyNet, equals(1300));
      },
    );
  });
}
