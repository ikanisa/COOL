import 'package:cool_app/core/status/models/cool_mission.dart';
import 'package:cool_app/shared/widgets/mission_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CoolMission _fakeMission({
  int totalProgress = 45,
  int targetValue = 100,
  int rewardPoints = 25,
  String? description = 'Keep your streak going to unlock the reward.',
}) {
  final now = DateTime.now();
  return CoolMission(
    id: 'mission-1',
    title: 'Contribution Streak',
    description: description,
    missionType: CoolMissionType.contributionStreak,
    targetValue: targetValue,
    scope: MissionScope.global,
    emoji: '🔥',
    startsAt: now.subtract(const Duration(days: 1)),
    endsAt: now.add(const Duration(days: 2)),
    rewardPoints: rewardPoints,
    isActive: true,
    totalProgress: totalProgress,
  );
}

void main() {
  group('MissionProgressCard', () {
    testWidgets('renders mission title, description, and reward', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(MissionProgressCard(mission: _fakeMission())),
      );

      expect(find.text('Contribution Streak'), findsOneWidget);
      expect(
        find.text('Keep your streak going to unlock the reward.'),
        findsOneWidget,
      );
      expect(find.text('25 Points'), findsOneWidget);
    });

    testWidgets('renders completion copy when mission is finished', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MissionProgressCard(
            mission: _fakeMission(totalProgress: 120, targetValue: 100),
          ),
        ),
      );

      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('invokes onTap when provided', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          MissionProgressCard(
            mission: _fakeMission(),
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(MissionProgressCard));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
