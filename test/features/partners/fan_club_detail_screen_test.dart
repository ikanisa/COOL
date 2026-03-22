import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/screens/fan_club_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fan club detail shows the redesigned operations brief', (
    tester,
  ) async {
    const club = RsFanClub(
      id: 'club-1',
      partnerId: 'partner-1',
      name: 'Kigali Blue',
      region: 'Kigali',
      description: 'Main chapter for city supporters.',
      memberCount: 120,
      eventCount: 5,
      rating: 4.8,
      bannerEmoji: '🥁',
    );
    final achievement = RsAchievement(
      id: 'achievement-1',
      userId: 'user-1',
      badgeType: 'chapter_lead',
      emoji: '🏆',
      name: 'Chapter Lead',
      description: 'Joined and led chapter mobilisation.',
      isEarned: true,
      earnedAt: DateTime(2026, 3, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rayonClubDirectoryProvider.overrideWith(
            (ref) => const AsyncData(
              RayonClubDirectoryData(clubs: [club], joinedClubIds: {'club-1'}),
            ),
          ),
          rayonUserAchievementsProvider.overrideWith(
            (ref) async => <RsAchievement>[achievement],
          ),
        ],
        child: const MaterialApp(home: FanClubDetailScreen(clubId: 'club-1')),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Chapter Operations Brief'), findsOneWidget);
    expect(find.text('Kigali Blue'), findsOneWidget);
  });
}
