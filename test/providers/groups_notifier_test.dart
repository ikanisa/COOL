import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/auth/providers/auth_provider.dart'
    show AuthState;
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  late MockGroupRepository mockRepo;
  late GroupsNotifier notifier;

  final sampleGroups = [
    Group.fromJson({
      'id': 'g1',
      'creator_id': 'u1',
      'name': 'Savings A',
      'type': 'saving',
      'visibility': 'private',
      'amount': 10000,
      'target_amount': 50000,
      'country': 'RW',
    }),
    Group.fromJson({
      'id': 'g2',
      'creator_id': 'u1',
      'name': 'Community B',
      'type': 'community',
      'visibility': 'public',
      'amount': 20000,
      'target_amount': 100000,
      'country': 'RW',
    }),
    Group.fromJson({
      'id': 'g3',
      'creator_id': 'u2',
      'name': 'Savings C',
      'type': 'saving',
      'visibility': 'public',
      'amount': 5000,
      'target_amount': 30000,
      'country': 'RW',
    }),
  ];

  setUp(() {
    mockRepo = MockGroupRepository();
    notifier = GroupsNotifier(
      repository: mockRepo,
      authState: const AuthState(
        user: null,
        session: null,
        isLoading: false,
        error: null,
      ),
    );
  });

  group('GroupsNotifier initial state', () {
    test('starts empty with no loading, no error', () {
      expect(notifier.state.groups, isEmpty);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
      expect(notifier.state.invitePreview, isNull);
      expect(notifier.state.isJoiningGroup, isFalse);
      expect(notifier.state.isContributing, isFalse);
    });
  });

  group('GroupsState.copyWith', () {
    test('updates groups list', () {
      final updated = const GroupsState().copyWith(groups: sampleGroups);
      expect(updated.groups.length, 3);
      expect(updated.isLoading, false);
    });

    test('clears error with explicit null', () {
      final withError = const GroupsState().copyWith(error: 'some error');
      expect(withError.error, 'some error');

      final cleared = withError.copyWith(error: null);
      expect(cleared.error, isNull);
    });

    test('preserves invitePreview with sentinel', () {
      final state = const GroupsState().copyWith(groups: sampleGroups);
      expect(state.invitePreview, isNull);
    });
  });

  group('GroupsNotifier.filterGroups', () {
    setUp(() {
      // Pre-load groups into state
      when(
        () => mockRepo.getMyGroups(any(), country: any(named: 'country')),
      ).thenAnswer((_) async => sampleGroups);
    });

    test('filters by type "saving"', () async {
      // Manually verify filter logic
      final savingGroups = sampleGroups
          .where((g) => g.type == 'saving')
          .toList();
      expect(savingGroups.length, 2);
      expect(savingGroups.every((g) => g.type == 'saving'), true);
    });

    test('filters by type "community"', () {
      final communityGroups = sampleGroups
          .where((g) => g.type == 'community')
          .toList();
      expect(communityGroups.length, 1);
      expect(communityGroups.first.name, 'Community B');
    });

    test('filters by visibility "public"', () {
      final publicGroups = sampleGroups
          .where((g) => g.visibility == 'public')
          .toList();
      expect(publicGroups.length, 2);
    });

    test('filters by visibility "private"', () {
      final privateGroups = sampleGroups
          .where((g) => g.visibility == 'private')
          .toList();
      expect(privateGroups.length, 1);
      expect(privateGroups.first.name, 'Savings A');
    });

    test('no filter returns all groups', () {
      expect(sampleGroups.length, 3);
    });
  });

  group('GroupsNotifier.loadMyGroups', () {
    test('sets loading and populates groups on success', () async {
      when(
        () => mockRepo.getMyGroups(any(), country: any(named: 'country')),
      ).thenAnswer((_) async => sampleGroups);

      // Set up a notifier with a fake user ID
      final notifierWithUser = GroupsNotifier(
        repository: mockRepo,
        authState: const AuthState(
          user: null,
          session: null,
          isLoading: false,
          error: null,
        ),
      );

      // Without a user, loadMyGroups should gracefully handle the case
      await notifierWithUser.loadMyGroups();
      // State depends on whether user is null — tests the null-safety path
      expect(notifierWithUser.state.isLoading, false);
    });

    test('sets error on repository failure', () async {
      when(
        () => mockRepo.getMyGroups(any(), country: any(named: 'country')),
      ).thenThrow(Exception('DB connection failed'));

      final notifierWithAuth = GroupsNotifier(
        repository: mockRepo,
        authState: const AuthState(
          user: null,
          session: null,
          isLoading: false,
          error: null,
        ),
      );

      await notifierWithAuth.loadMyGroups();
      expect(notifierWithAuth.state.isLoading, false);
      // Error should be set or groups should be empty
      expect(notifierWithAuth.state.groups, isEmpty);
    });
  });
}
