import 'package:cool_app/features/home/models/home_dashboard_data.dart';
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

    test('merges contribution and wallet rows, sorted by date descending', () {
      final transactions = buildHomeRecentTransactions(
        contributionRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'group_id': 'g1',
            'user_id': 'u1',
            'amount': 10000,
            'status': 'confirmed',
            'created_at': '2026-03-10T08:00:00Z',
          },
        ],
        walletRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'entry_type': 'credit',
            'amount': 500,
            'tx_datetime': '2026-03-12T09:00:00Z',
            'statement_label': 'Wallet credit',
          },
        ],
        groupsById: <String, String>{'g1': 'Savings Club'},
      );

      expect(transactions, hasLength(2));
      // Most recent first (wallet on Mar 12, contribution on Mar 10)
      expect(transactions[0].title, equals('Wallet credit'));
      expect(transactions[1].title, contains('Savings Club'));
    });

    test('limits output to 8 transactions by default', () {
      final walletRows = List.generate(
        15,
        (index) => <String, dynamic>{
          'entry_type': 'credit',
          'amount': 100 + index,
          'tx_datetime':
              '2026-03-${(index + 1).toString().padLeft(2, '0')}T09:00:00Z',
          'statement_label': 'Tx $index',
        },
      );

      final transactions = buildHomeRecentTransactions(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: walletRows,
        groupsById: const <String, String>{},
      );

      expect(transactions.length, 8);
    });

    test('returns empty list when both inputs are empty', () {
      final transactions = buildHomeRecentTransactions(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: const <Map<String, dynamic>>[],
        groupsById: const <String, String>{},
      );

      expect(transactions, isEmpty);
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

    test('returns 0 for empty inputs', () {
      final monthlyNet = calculateHomeMonthlyNetChange(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: const <Map<String, dynamic>>[],
        now: DateTime.utc(2026, 3, 12),
      );

      expect(monthlyNet, 0);
    });

    test('credits only produces a positive net', () {
      final monthlyNet = calculateHomeMonthlyNetChange(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'entry_type': 'credit',
            'amount': 5000,
            'tx_datetime': '2026-03-05T09:00:00Z',
          },
        ],
        now: DateTime.utc(2026, 3, 12),
      );

      expect(monthlyNet, 5000);
    });

    test('debits only produces a negative net', () {
      final monthlyNet = calculateHomeMonthlyNetChange(
        contributionRows: const <Map<String, dynamic>>[],
        walletRows: <Map<String, dynamic>>[
          <String, dynamic>{
            'entry_type': 'debit',
            'amount': 3000,
            'tx_datetime': '2026-03-05T09:00:00Z',
          },
        ],
        now: DateTime.utc(2026, 3, 12),
      );

      expect(monthlyNet, -3000);
    });
  });

  group('HomeDashboardTransaction', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);

    test('isPositive returns true for credit type', () {
      final tx = HomeDashboardTransaction(
        title: 'Received',
        type: 'credit',
        amount: 500,
        currency: 'RWF',
        recordedAt: epoch,
      );
      expect(tx.isPositive, isTrue);
    });

    test('isPositive returns true for deposit type', () {
      final tx = HomeDashboardTransaction(
        title: 'Deposit',
        type: 'deposit',
        amount: 1000,
        currency: 'RWF',
        recordedAt: epoch,
      );
      expect(tx.isPositive, isTrue);
    });

    test('isPositive returns false for debit type', () {
      final tx = HomeDashboardTransaction(
        title: 'Sent',
        type: 'debit',
        amount: 200,
        currency: 'RWF',
        recordedAt: epoch,
      );
      expect(tx.isPositive, isFalse);
    });

    test('signedAmount returns positive for credit', () {
      final tx = HomeDashboardTransaction(
        title: 'Received',
        type: 'credit',
        amount: 500,
        currency: 'RWF',
        recordedAt: epoch,
      );
      expect(tx.signedAmount, 500);
    });

    test('signedAmount returns negative for debit', () {
      final tx = HomeDashboardTransaction(
        title: 'Sent',
        type: 'debit',
        amount: 300,
        currency: 'RWF',
        recordedAt: epoch,
      );
      expect(tx.signedAmount, -300);
    });
  });

  group('HomeDashboardData', () {
    test('stores all fields correctly', () {
      const data = HomeDashboardData(
        totalBalance: 250000,
        monthlyNetChange: 15000,
        memberCount: 3,
      );

      expect(data.totalBalance, 250000);
      expect(data.monthlyNetChange, 15000);
      expect(data.memberCount, 3);
      expect(data.recentTransactions, isEmpty);
    });
  });
}
