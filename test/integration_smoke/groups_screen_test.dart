import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';

import 'test_harness.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('Groups screen smoke', () {
    late MockGroupRepository repository;

    setUp(() {
      repository = MockGroupRepository();
      when(
        () => repository.getMyGroups(any(), country: any(named: 'country')),
      ).thenAnswer(
        (_) async => [
          const Group(
            id: 'g1',
            creatorId: 'u1',
            name: 'Family Save',
            type: 'saving',
            visibility: 'private',
            amount: 50000,
            targetAmount: 100000,
            memberCount: 2,
            country: 'RW',
            frequency: 'monthly',
          ),
        ],
      );
      when(() => repository.getPublicGroups(any())).thenAnswer(
        (_) async => [
          const Group(
            id: 'g2',
            creatorId: 'u2',
            name: 'Neighborhood Relief',
            type: 'community',
            visibility: 'public',
            amount: 25000,
            targetAmount: 500000,
            memberCount: 12,
            country: 'RW',
            frequency: 'monthly',
          ),
        ],
      );
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
      expect(find.text('Family Save'), findsOneWidget);

      await tester.tap(find.text('Discover'));
      await settleTestApp(tester);

      expect(find.text('Neighborhood Relief'), findsOneWidget);
      verify(() => repository.getPublicGroups(any())).called(greaterThan(0));
    });
  });
}
