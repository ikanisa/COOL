import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_contribution.dart';
import 'package:cool_app/features/groups/models/group_detail.dart';
import 'package:cool_app/features/groups/models/group_member.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/group_detail_screen.dart';

import 'test_harness.dart';

class _MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('Group detail smoke', () {
    late _MockGroupRepository repository;

    final detail = GroupDetail(
      group: const Group(
        id: 'group-1',
        creatorId: 'user-1',
        name: 'Family Save',
        type: 'saving',
        visibility: 'private',
        amount: 80000,
        targetAmount: 150000,
        memberCount: 5,
        country: 'RW',
        bankPartner: 'BK Rwanda',
        frequency: 'monthly',
        description: 'Emergency savings for the household.',
      ),
      members: const <GroupMember>[
        GroupMember(
          userId: 'user-1',
          displayName: 'Alex Fan',
          contributionAmount: 25000,
          isAdmin: true,
        ),
        GroupMember(
          userId: 'user-2',
          displayName: 'Chris Fan',
          contributionAmount: 20000,
        ),
        GroupMember(
          userId: 'user-3',
          displayName: 'Pat Fan',
          contributionAmount: 15000,
        ),
        GroupMember(
          userId: 'user-4',
          displayName: 'Jamie Fan',
          contributionAmount: 10000,
        ),
        GroupMember(
          userId: 'user-5',
          displayName: 'Taylor Fan',
          contributionAmount: 10000,
        ),
      ],
      recentContributions: <GroupContribution>[
        GroupContribution(
          groupId: 'group-1',
          userId: 'user-2',
          amount: 20000,
          status: 'completed',
          contributorName: 'Chris Fan',
          createdAt: DateTime(2026, 3, 10),
        ),
        GroupContribution(
          groupId: 'group-1',
          userId: 'user-3',
          amount: 15000,
          status: 'completed',
          contributorName: 'Pat Fan',
          createdAt: DateTime(2026, 3, 5),
        ),
        GroupContribution(
          groupId: 'group-1',
          userId: 'user-4',
          amount: 10000,
          status: 'completed',
          contributorName: 'Jamie Fan',
          createdAt: DateTime(2026, 3, 1),
        ),
        GroupContribution(
          groupId: 'group-1',
          userId: 'user-5',
          amount: 10000,
          status: 'completed',
          contributorName: 'Taylor Fan',
          createdAt: DateTime(2026, 2, 24),
        ),
      ],
      isMember: true,
    );

    setUp(() {
      repository = _MockGroupRepository();
      when(
        () => repository.getGroupById(any(), country: any(named: 'country')),
      ).thenAnswer((_) async => detail);
    });

    testWidgets(
      'keeps contribute primary and moves share actions behind More',
      (tester) async {
        await pumpScopedApp(
          tester,
          child: const GroupDetailScreen(groupId: 'group-1'),
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            groupRepositoryProvider.overrideWithValue(repository),
          ],
        );

        await settleTestApp(tester);

        expect(find.text('+ Contribute'), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
        expect(find.text('Group facts'), findsOneWidget);
        expect(find.text('Recent contributions'), findsOneWidget);
        expect(find.text('Share / QR'), findsNothing);
        expect(find.text('Invite from Contacts'), findsNothing);

        await tester.tap(find.text('More'));
        await settleTestApp(tester);

        expect(find.text('More actions'), findsOneWidget);
        expect(find.text('Share / QR'), findsOneWidget);
        expect(find.text('Invite from Contacts'), findsOneWidget);
      },
    );
  });
}
