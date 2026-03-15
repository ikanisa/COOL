import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';

import 'test_harness.dart';

class _MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('Groups screen smoke', () {
    late _MockGroupRepository repository;

    const myGroup = Group(
      id: 'group-1',
      creatorId: 'user-1',
      name: 'Family Save',
      type: 'saving',
      visibility: 'private',
      amount: 80000,
      targetAmount: 150000,
      memberCount: 4,
      country: 'RW',
      bankPartner: 'BK Rwanda',
      frequency: 'monthly',
    );

    const publicGroup = Group(
      id: 'group-2',
      creatorId: 'user-9',
      name: 'Neighborhood Relief',
      type: 'community',
      visibility: 'public',
      amount: 45000,
      targetAmount: 100000,
      memberCount: 12,
      country: 'RW',
      momoNumber: '+250788123456',
      frequency: 'weekly',
    );

    setUp(() {
      repository = _MockGroupRepository();
      when(
        () => repository.getMyGroups(any(), country: any(named: 'country')),
      ).thenAnswer((_) async => const <Group>[myGroup]);
      when(
        () => repository.getPublicGroups(any()),
      ).thenAnswer((_) async => const <Group>[publicGroup]);
    });

    testWidgets('uses My Groups and Discover as the primary split', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const GroupsScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          groupRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await settleTestApp(tester);

      expect(find.text('My Groups'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Create a New Group'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Family Save'), findsOneWidget);

      await tester.tap(find.text('Filters'));
      await settleTestApp(tester);

      expect(find.text('My group filters'), findsOneWidget);
      expect(find.text('All types'), findsOneWidget);
      expect(find.text('Private only'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await settleTestApp(tester);

      await tester.tap(find.text('Discover'));
      await settleTestApp(tester);

      expect(find.text('Discover groups'), findsOneWidget);
      expect(find.text('Neighborhood Relief'), findsOneWidget);
      expect(find.text('Filters'), findsNothing);
      verify(() => repository.getPublicGroups(any())).called(greaterThan(0));
    });
  });
}
