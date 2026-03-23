import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/engagement_tracker.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_detail.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/group_invite_screen.dart';

import '../../integration_smoke/test_harness.dart';

class _MockGroupRepository extends Mock implements GroupRepository {}

class _MockEngagementTracker extends Mock implements EngagementTracker {}

void main() {
  group('Group invite screen', () {
    late _MockGroupRepository repository;
    late _MockEngagementTracker engagementTracker;

    const detail = GroupDetail(
      group: Group(
        id: 'group-1',
        creatorId: 'user-1',
        name: 'Neighbourhood Save',
        type: 'saving',
        visibility: 'public',
        amount: 45000,
        targetAmount: 120000,
        memberCount: 8,
        country: 'RW',
        frequency: 'monthly',
        description: 'Build a rainy-day fund together.',
        inviteCode: 'TEAM1234',
      ),
      isMember: false,
    );

    setUp(() {
      repository = _MockGroupRepository();
      engagementTracker = _MockEngagementTracker();

      when(
        () => repository.getGroupByInviteCode(
          any(),
          country: any(named: 'country'),
        ),
      ).thenAnswer((_) async => detail);
      when(
        () => engagementTracker.trackInviteOpened(
          inviteCode: any(named: 'inviteCode'),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async {});
    });

    testWidgets('renders preview details and join CTA', (tester) async {
      await pumpScopedApp(
        tester,
        child: const GroupInviteScreen(inviteCode: 'team1234'),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          groupRepositoryProvider.overrideWithValue(repository),
          engagementTrackerProvider.overrideWithValue(engagementTracker),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('Group invite'), findsOneWidget);
      expect(find.text('Invite code TEAM1234'), findsOneWidget);
      expect(find.text('Neighbourhood Save'), findsOneWidget);
      expect(find.text('8 members'), findsOneWidget);
      expect(find.text('Monthly contributions'), findsOneWidget);
      expect(find.text('Build a rainy-day fund together.'), findsOneWidget);
      expect(find.text('You will join this group.'), findsOneWidget);
      expect(find.text('Join Group'), findsOneWidget);

      verify(
        () => engagementTracker.trackInviteOpened(
          inviteCode: 'team1234',
          queryParameters: const <String, String>{},
        ),
      ).called(1);
    });
  });
}
