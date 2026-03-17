import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/shared/widgets/cool_status_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

CoolStatus _fakeStatus({
  FanTier tier = FanTier.silver,
  int totalPoints = 150,
  int currentStreak = 7,
  int longestStreak = 14,
  int streakGraceRemaining = 1,
}) =>
    CoolStatus(
      id: 'status-1',
      userId: 'user-1',
      totalPoints: totalPoints,
      tier: tier,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      streakGraceRemaining: streakGraceRemaining,
      seasonPoints: 50,
      updatedAt: DateTime(2026),
      createdAt: DateTime(2026),
    );

void main() {
  group('CoolStatusCard', () {
    testWidgets('renders tier label', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(status: _fakeStatus(tier: FanTier.silver)),
      ));
      expect(find.text('Silver Member'), findsOneWidget);
    });

    testWidgets('renders points pill', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(status: _fakeStatus(totalPoints: 250)),
      ));
      expect(find.text('250 Tokens'), findsOneWidget);
    });

    testWidgets('renders streak info', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(
          status: _fakeStatus(currentStreak: 7, longestStreak: 14),
        ),
      ));
      expect(find.text('7 streak'), findsOneWidget);
      expect(find.text('14 best'), findsOneWidget);
    });

    testWidgets('shows progress bar for non-platinum tier', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(status: _fakeStatus(tier: FanTier.gold)),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('hides progress bar for platinum tier', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(
          status: _fakeStatus(tier: FanTier.platinum, totalPoints: 600),
        ),
      ));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows grace pill when grace remaining > 0', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolStatusCard(
          status: _fakeStatus(streakGraceRemaining: 2),
        ),
      ));
      expect(find.text('2 grace'), findsOneWidget);
    });
  });
}
