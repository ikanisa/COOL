import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_access_snapshot.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/group_settings_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakeGroupRepository extends GroupRepository {
  _FakeGroupRepository() : super(client: _MockSupabaseClient());

  String? savedGroupId;
  String? savedName;
  String? savedDescription;
  int? savedTargetAmount;
  int? savedMonthlyContribution;
  String? savedFrequency;
  MomoRecipientType? savedRouteType;
  String? savedRecipientValue;
  int updateCalls = 0;

  @override
  Future<Group> updateGroupSavingsSettings({
    required String groupId,
    required String name,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    String? frequency,
    MomoRecipientType? customMomoRouteType,
    String? customRecipientValue,
  }) async {
    updateCalls += 1;
    savedGroupId = groupId;
    savedName = name;
    savedDescription = description;
    savedTargetAmount = targetAmount;
    savedMonthlyContribution = monthlyContribution;
    savedFrequency = frequency;
    savedRouteType = customMomoRouteType;
    savedRecipientValue = customRecipientValue;
    return _group.copyWith(
      name: name,
      description: description,
      targetAmount: targetAmount ?? 0,
      monthlyContribution: monthlyContribution,
      frequency: frequency,
      momoRouteType: customMomoRouteType == MomoRecipientType.code
          ? 'code'
          : 'phone_number',
      momoNumber: customRecipientValue,
    );
  }
}

void main() {
  testWidgets('saves seeded group settings through the repository', (
    tester,
  ) async {
    final repository = _FakeGroupRepository();
    final router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
          routes: <RouteBase>[
            GoRoute(
              path: 'settings',
              builder: (context, state) =>
                  const GroupSettingsScreen(groupId: 'group-1'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          groupRepositoryProvider.overrideWithValue(repository),
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
        ],
        child: MaterialApp.router(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.savedGroupId, 'group-1');
    expect(repository.savedName, 'Alpha Circle');
    expect(repository.savedDescription, 'Shared goal');
    expect(repository.savedTargetAmount, 500000);
    expect(repository.savedMonthlyContribution, 25000);
    expect(repository.savedFrequency, 'monthly');
    expect(repository.savedRouteType, MomoRecipientType.code);
    expect(repository.savedRecipientValue, '23456');
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
  momoNumber: '23456',
  momoRouteType: 'code',
  frequency: 'monthly',
);
