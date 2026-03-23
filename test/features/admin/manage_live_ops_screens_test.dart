import 'package:cool_app/core/status/models/cool_activity.dart';
import 'package:cool_app/core/status/models/cool_mission.dart';
import 'package:cool_app/core/status/models/cool_season.dart';
import 'package:cool_app/features/admin/providers/admin_gamification_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_gamification_repository.dart';
import 'package:cool_app/features/admin/screens/manage_activities_screen.dart';
import 'package:cool_app/features/admin/screens/manage_missions_screen.dart';
import 'package:cool_app/features/admin/screens/manage_seasons_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeAdminGamificationRepository extends AdminGamificationRepository {
  FakeAdminGamificationRepository({
    List<CoolMission> missions = const <CoolMission>[],
    List<CoolSeason> seasons = const <CoolSeason>[],
    List<CoolActivity> activities = const <CoolActivity>[],
  }) : _missions = List<CoolMission>.from(missions),
       _seasons = List<CoolSeason>.from(seasons),
       _activities = List<CoolActivity>.from(activities),
       super(client: MockSupabaseClient());

  final List<CoolMission> _missions;
  final List<CoolSeason> _seasons;
  final List<CoolActivity> _activities;

  final List<Map<String, dynamic>> toggledMissions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> toggledSeasons = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> toggledActivities = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> upsertedMissions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> upsertedSeasons = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> upsertedActivities =
      <Map<String, dynamic>>[];

  @override
  Future<List<CoolMission>> listMissions() async =>
      List<CoolMission>.from(_missions);

  @override
  Future<List<CoolSeason>> listSeasons() async =>
      List<CoolSeason>.from(_seasons);

  @override
  Future<List<CoolActivity>> listActivities() async =>
      List<CoolActivity>.from(_activities);

  @override
  Future<void> toggleMissionActive(String id, {required bool isActive}) async {
    toggledMissions.add(<String, dynamic>{'id': id, 'isActive': isActive});
  }

  @override
  Future<void> toggleSeasonActive(String id, {required bool isActive}) async {
    toggledSeasons.add(<String, dynamic>{'id': id, 'isActive': isActive});
  }

  @override
  Future<void> toggleActivityActive(String id, {required bool isActive}) async {
    toggledActivities.add(<String, dynamic>{'id': id, 'isActive': isActive});
  }

  @override
  Future<void> upsertMission(Map<String, dynamic> data) async {
    upsertedMissions.add(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> upsertSeason(Map<String, dynamic> data) async {
    upsertedSeasons.add(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> upsertActivity(Map<String, dynamic> data) async {
    upsertedActivities.add(Map<String, dynamic>.from(data));
  }
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('missions screen renders and toggles mission state', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeAdminGamificationRepository(
      missions: <CoolMission>[
        CoolMission(
          id: 'mission-1',
          title: 'Savings Drive',
          missionType: CoolMissionType.savingsSprint,
          targetValue: 50,
          scope: MissionScope.global,
          emoji: '🎯',
          startsAt: DateTime.now().subtract(const Duration(days: 1)),
          endsAt: DateTime.now().add(const Duration(days: 7)),
          rewardPoints: 100,
          isActive: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminGamificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageMissionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Missions'), findsOneWidget);
    expect(find.text('Savings Drive'), findsOneWidget);

    await tester.tap(find.byTooltip('Deactivate mission'));
    await tester.pumpAndSettle();

    expect(repository.toggledMissions, hasLength(1));
    expect(repository.toggledMissions.single['id'], 'mission-1');
    expect(repository.toggledMissions.single['isActive'], isFalse);
  });

  testWidgets('seasons screen creates a season from the editor sheet', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeAdminGamificationRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminGamificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageSeasonsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Title'), 'Supporter Week');
    await tester.tap(find.text('Create Season').last);
    await tester.pumpAndSettle();

    expect(repository.upsertedSeasons, hasLength(1));
    expect(repository.upsertedSeasons.single['title'], 'Supporter Week');
    expect(repository.upsertedSeasons.single['theme'], 'savings');
  });

  testWidgets('activities screen creates an activity from the editor sheet', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeAdminGamificationRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminGamificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageActivitiesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Title'), 'Share Referral');
    await tester.enterText(_textFieldWithLabel('Slug'), 'share-referral');
    await tester.enterText(_textFieldWithLabel('Tokens Awarded'), '45');

    await tester.tap(find.text('Create Activity').last);
    await tester.pumpAndSettle();

    expect(repository.upsertedActivities, hasLength(1));
    expect(repository.upsertedActivities.single['title'], 'Share Referral');
    expect(repository.upsertedActivities.single['slug'], 'share-referral');
    expect(repository.upsertedActivities.single['tokens_awarded'], 45);
  });
}
