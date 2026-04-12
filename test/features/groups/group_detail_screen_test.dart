import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_access_snapshot.dart';
import 'package:cool_app/features/groups/models/group_member_preview.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/screens/group_detail_screen.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/core_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows settings and statements access for a managing member', (
    tester,
  ) async {
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
          groupMemberPreviewProvider(
            'group-1',
          ).overrideWith((ref) async => const <GroupMemberPreview>[]),
          groupTransactionFeedProvider(
            const GroupPaymentLedgerQuery(
              groupId: 'group-1',
              statementQuery: MomoStatementQuery(limit: 10),
            ),
          ).overrideWith(
            (ref) async => const MomoStatementPage<PayeePaymentLedgerEntry>(),
          ),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupDetailScreen(groupId: 'group-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CoreDetailScaffold), findsOneWidget);
    expect(find.byType(CoolCard), findsWidgets);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.text('Alpha Group'), findsOneWidget);
    expect(find.text('JOIN GROUP'), findsNothing);
  });

  testWidgets('shows members preview for a public group before joining', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          groupDetailProvider(
            'group-1',
          ).overrideWith((ref) async => _publicGroup),
          groupAccessProvider('group-1').overrideWith(
            (ref) async => const GroupAccessSnapshot(
              groupId: 'group-1',
              isMember: false,
              isCreator: false,
              isGroupAdmin: false,
              isBankCustodyAdmin: false,
              canViewTransactions: false,
              canManageSettings: false,
              canExportLedger: false,
            ),
          ),
          groupMemberPreviewProvider('group-1').overrideWith(
            (ref) async => const <GroupMemberPreview>[
              GroupMemberPreview(
                displayName: '123456',
                isAdmin: true,
                isAnonymous: false,
              ),
              GroupMemberPreview(
                displayName: 'Anonymous member',
                isAdmin: false,
                isAnonymous: true,
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupDetailScreen(groupId: 'group-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Members preview'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('Anonymous member'), findsOneWidget);
  });
}

const _group = Group(
  id: 'group-1',
  creatorId: 'user-1',
  name: 'Alpha Group',
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

const _publicGroup = Group(
  id: 'group-1',
  creatorId: 'user-2',
  name: 'Open Group',
  type: 'community',
  visibility: 'public',
  amount: 50000,
  targetAmount: 0,
  country: 'RW',
  memberCount: 2,
  description: 'Public group',
);
