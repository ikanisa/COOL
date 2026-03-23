import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_contribution.dart';
import 'package:cool_app/features/groups/models/group_detail.dart';
import 'package:cool_app/features/groups/models/group_member.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/group_ledger_screen.dart';

import '../../integration_smoke/test_harness.dart';

class _MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('Group ledger screen', () {
    late _MockGroupRepository repository;

    const detail = GroupDetail(
      group: Group(
        id: 'group-1',
        creatorId: 'user-1',
        name: 'Family Save',
        type: 'saving',
        visibility: 'private',
        amount: 35000,
        targetAmount: 100000,
        memberCount: 2,
        country: 'RW',
      ),
      members: <GroupMember>[
        GroupMember(
          userId: 'user-1',
          displayName: 'Alex Fan',
          contributionAmount: 20000,
          isAdmin: true,
        ),
        GroupMember(
          userId: 'user-2',
          displayName: 'Chris Fan',
          contributionAmount: 15000,
        ),
      ],
      isMember: true,
    );

    final entries = <GroupContribution>[
      GroupContribution(
        groupId: 'group-1',
        userId: 'user-1',
        amount: 20000,
        status: 'completed',
        contributorName: 'Alex Fan',
        createdAt: DateTime(2026, 3, 10, 9, 30),
      ),
      GroupContribution(
        groupId: 'group-1',
        userId: 'user-2',
        amount: 15000,
        status: 'pending',
        contributorName: 'Chris Fan',
        createdAt: DateTime(2026, 3, 8, 15, 45),
      ),
    ];

    setUp(() {
      repository = _MockGroupRepository();
      when(
        () => repository.getGroupById(any(), country: any(named: 'country')),
      ).thenAnswer((_) async => detail);
      when(
        () => repository.fetchAllContributions(
          any(),
          userId: any(named: 'userId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => entries);
    });

    testWidgets('renders summary metrics and contribution rows', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const GroupLedgerScreen(groupId: 'group-1'),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          groupRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Family Save'), findsOneWidget);
      expect(find.text('RWF 35,000'), findsOneWidget);
      expect(find.text('Alex Fan'), findsOneWidget);
      expect(find.text('Chris Fan'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });
  });
}
