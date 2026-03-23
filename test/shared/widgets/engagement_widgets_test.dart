import 'package:cool_app/core/status/models/cool_season.dart';
import 'package:cool_app/core/status/services/quest_engine.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/group_card.dart';
import 'package:cool_app/shared/widgets/quest_card.dart';
import 'package:cool_app/shared/widgets/season_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _wrap(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CoolSeason _liveSeason({
  bool isActive = true,
  String? rewardsDescription = 'Top fans unlock premium matchday drops.',
}) {
  final now = DateTime.now();
  return CoolSeason(
    id: 'season-1',
    title: 'Matchday Momentum',
    theme: 'matchday',
    emoji: '⚽',
    startsAt: now.subtract(const Duration(days: 2)),
    endsAt: now.add(const Duration(days: 5)),
    isActive: isActive,
    rewardsDescription: rewardsDescription,
  );
}

void main() {
  group('engagement widgets', () {
    testWidgets('GroupCard renders formatted amount and target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          GroupCard(
            name: 'Goal Getters',
            type: 'saving',
            visibility: 'public',
            amount: 125000,
            memberCount: 5,
            targetAmount: 300000,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Goal Getters'), findsOneWidget);
      expect(find.text('125,000 RWF'), findsOneWidget);
      expect(find.text('Target: 300,000 RWF'), findsOneWidget);
    });

    testWidgets('QuestCard navigates to the quest route on tap', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: QuestCard(
                quest: const CoolQuest(
                  id: 'quest-1',
                  icon: Icons.flag_rounded,
                  title: 'Complete onboarding',
                  subtitle: 'Finish setup to unlock your first reward.',
                  route: '/quests/1',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/quests/1',
            builder: (context, state) =>
                const Scaffold(body: Text('quest destination')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(QuestCard));
      await tester.pumpAndSettle();

      expect(find.text('quest destination'), findsOneWidget);
    });

    testWidgets('SeasonBanner renders only for live seasons', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              SeasonBanner(
                season: _liveSeason(),
                seasonPoints: 90,
                onTap: () {},
              ),
              SeasonBanner(
                season: _liveSeason(isActive: false, rewardsDescription: null),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Matchday Momentum'), findsOneWidget);
      expect(find.text('90 Tokens'), findsOneWidget);
      expect(
        find.text('Top fans unlock premium matchday drops.'),
        findsOneWidget,
      );
    });
  });
}
