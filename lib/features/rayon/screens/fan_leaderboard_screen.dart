import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/theme/rs_text_styles.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/rs_tier_badge.dart';
import '../models/rs_models.dart';
import '../providers/rs_engagement_provider.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/rayon_state_views.dart';

part '../widgets/fan_leaderboard_parts.dart';

/// Fan Leaderboard — global ranking by prediction XP.
class FanLeaderboardScreen extends ConsumerWidget {
  const FanLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final leaderboardAsync = ref.watch(fanLeaderboardProvider);

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: buildPartnerBackButton(
              context,
              fallbackLocation: AppRoutes.gamification,
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FAN ',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
                Text(
                  'LEADERBOARD',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsRed),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                color: colors.secondaryText,
                onPressed: () => ref.invalidate(fanLeaderboardProvider),
              ),
            ],
          ),
          leaderboardAsync.when(
            loading: () => const SliverFillRemaining(
              child: RayonInlineLoadingView(compact: false),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: colors.secondaryText, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load leaderboard',
                        style: RsTextStyles.badge(color: colors.secondaryText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🏆', style: TextStyle(fontSize: 56)),
                          const SizedBox(height: 16),
                          Text(
                            'No predictions yet',
                            style: RsTextStyles.sectionTitle(
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Be the first to predict a match score!',
                            style: RsTextStyles.badge(
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Separate top 3 + rest
              final top3 = entries.take(3).toList();
              final rest = entries.skip(3).toList();

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 12),
                    _TopThreeSpotlight(entries: top3),
                    const SizedBox(height: CoolSpace.x6),
                    if (rest.isNotEmpty) ...[
                      _SectionLabel(label: 'RANKINGS', count: entries.length),
                      const SizedBox(height: CoolSpace.x4),
                      for (final entry in rest) ...[
                        _LeaderboardTile(entry: entry),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
