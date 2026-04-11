import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:cool_app/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders shared group cards with shared badges and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          myGroupsProvider.overrideWith((ref) async => <Group>[_group]),
        ],
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupsScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alpha Circle'), findsOneWidget);
    expect(find.byType(CoolCard), findsWidgets);
    expect(find.byType(StatusBadge), findsWidgets);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
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
