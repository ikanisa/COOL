import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_access_snapshot.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/screens/group_statements_screen.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads more member feed rows without export actions', (
    tester,
  ) async {
    var lastLimit = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          groupDetailProvider('group-1').overrideWith((ref) async => _group),
          groupAccessProvider('group-1').overrideWith(
            (ref) async => const GroupAccessSnapshot(
              groupId: 'group-1',
              isMember: true,
              isCreator: false,
              isGroupAdmin: false,
              isBankCustodyAdmin: false,
              canViewTransactions: true,
              canManageSettings: false,
              canExportLedger: false,
            ),
          ),
          groupTransactionFeedProvider.overrideWith((ref, request) async {
            lastLimit = request.statementQuery.limit;
            if (request.statementQuery.limit > 50) {
              return MomoStatementPage<PayeePaymentLedgerEntry>(
                entries: <PayeePaymentLedgerEntry>[
                  _entry('ledger-1', 'Weekly contribution'),
                  _entry('ledger-2', 'Monthly top-up'),
                ],
                totalCount: 2,
              );
            }
            return MomoStatementPage<PayeePaymentLedgerEntry>(
              entries: <PayeePaymentLedgerEntry>[
                _entry('ledger-1', 'Weekly contribution'),
              ],
              totalCount: 2,
            );
          }),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupStatementsScreen(groupId: 'group-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsNothing);
    expect(find.byIcon(Icons.grid_on_rounded), findsNothing);
    expect(find.text('Weekly contribution'), findsOneWidget);
    expect(find.text('Monthly top-up'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_circle_down_rounded));
    await tester.pumpAndSettle();

    expect(lastLimit, 100);
    expect(find.text('Monthly top-up'), findsOneWidget);
  });

  testWidgets('shows export actions for group admins', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          groupDetailProvider('group-1').overrideWith((ref) async => _group),
          groupAccessProvider('group-1').overrideWith(
            (ref) async => const GroupAccessSnapshot(
              groupId: 'group-1',
              isMember: true,
              isCreator: true,
              isGroupAdmin: true,
              isBankCustodyAdmin: false,
              canViewTransactions: true,
              canManageSettings: true,
              canExportLedger: true,
            ),
          ),
          groupTransactionFeedProvider.overrideWith(
            (ref, request) async => MomoStatementPage<PayeePaymentLedgerEntry>(
              entries: <PayeePaymentLedgerEntry>[
                _entry('ledger-1', 'Weekly contribution'),
              ],
              totalCount: 1,
            ),
          ),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupStatementsScreen(groupId: 'group-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
    expect(find.byIcon(Icons.grid_on_rounded), findsOneWidget);
  });
}

const _group = Group(
  id: 'group-1',
  creatorId: 'user-1',
  name: 'Alpha Circle',
  type: 'saving',
  visibility: 'private',
  amount: 120000,
  targetAmount: 500000,
  country: 'RW',
  memberCount: 4,
  monthlyContribution: 25000,
  description: 'Shared goal',
  momoNumber: '0788123456',
  momoRouteType: 'phone_number',
  frequency: 'monthly',
);

PayeePaymentLedgerEntry _entry(String ledgerId, String label) {
  return PayeePaymentLedgerEntry(
    ledgerId: ledgerId,
    payerUserId: 'user-$ledgerId',
    payerName: 'Member',
    amount: 25000,
    currency: 'RWF',
    occurredAt: DateTime(2026, 4, 10, 12),
    txCategory: 'group_contribution',
    cashflowBucket: 'savings',
    label: label,
    targetTable: 'group_contributions',
    reference: 'MOMO-$ledgerId',
  );
}
