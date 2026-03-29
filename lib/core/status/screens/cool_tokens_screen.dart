import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_status_card.dart';
import '../../../shared/widgets/mission_progress_card.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/rayon/models/rs_models.dart';
import '../models/cool_activity.dart';
import '../models/cool_leaderboard_entry.dart';
import '../models/cool_reward.dart';
import '../providers/cool_activities_provider.dart';
import '../providers/cool_leaderboard_provider.dart';
import '../providers/cool_missions_provider.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/cool_status_provider.dart';
import '../widgets/referral_banner.dart';
import '../../../core/l10n/l10n.dart';

/// Full-page rewards hub for fans.
class CoolTokensScreen extends ConsumerWidget {
  const CoolTokensScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final userId = ref.watch(authProvider).user?.id ?? '';
    final status = ref.watch(coolStatusProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.rewardsProgram)),
      body: CoolScreenBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── App bar ─────────────────────────────────
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.home);
                    }
                  },
                  tooltip: context.l10n.back,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.primaryText,
                  ),
                ),
                title: Text(
                  'Fan Rewards',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                centerTitle: false,
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(space.x4, space.x2, space.x4, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── 1. Hero Card (tier + points + progress) ──
                    if (status != null) ...[
                      CoolStatusCard(status: status),
                      SizedBox(height: space.x3),
                      const ReferralBanner(),
                      SizedBox(height: space.x5),
                    ],

                    // ── 2. Streak & Stats ─────────────────────
                    if (status != null) ...[
                      _StreakStatsRow(status: status),
                      SizedBox(height: space.x6),
                    ],

                    // ── 3. Ways to Earn ───────────────────────
                    const _SectionHeader(
                      label: 'Welcome to Fan Rewards',
                      icon: Icons.auto_awesome_rounded,
                    ),
                    SizedBox(height: space.x2),
                    const _WaysToEarnGrid(),
                    SizedBox(height: space.x6),

                    // ── 4. Reward Activities ──────────────────
                    _SectionHeader(
                      label: context.l10n.activeMissions,
                      icon: Icons.flag_rounded,
                      trailing: TextButton(
                        onPressed: () => context.push(AppRoutes.missions),
                        child: Text(
                          'View all',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: space.x2),
                    _ActiveMissionsSection(userId: userId),
                    SizedBox(height: space.x6),

                    // ── 4.5 Rewards Marketplace ───────────────
                    const _SectionHeader(
                      label: 'Rewards Marketplace',
                      icon: Icons.redeem_rounded,
                    ),
                    SizedBox(height: space.x2),
                    _RewardsMarketplace(
                      userId: userId,
                      currentPoints: status?.totalPoints ?? 0,
                    ),
                    SizedBox(height: space.x6),

                    // ── 5. Leaderboard ────────────────────────
                    _SectionHeader(
                      label: 'Top Fans',
                      icon: Icons.leaderboard_rounded,
                      trailing: TextButton(
                        onPressed: () => context.push(AppRoutes.leaderboard),
                        child: Text(
                          'View all',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: space.x2),
                    const _TopEarnersSection(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Streak & stats row ────────────────────────────────────────────

class _StreakStatsRow extends StatelessWidget {
  const _StreakStatsRow({required this.status});

  final dynamic status; // CoolStatus

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            iconColor: colors.warning,
            label: context.l10n.currentStreak,
            value: '${status.currentStreak}',
            suffix: 'days',
          ),
        ),
        SizedBox(width: space.x2),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            iconColor: colors.warning,
            label: context.l10n.bestStreak,
            value: '${status.longestStreak}',
            suffix: 'days',
          ),
        ),
        SizedBox(width: space.x2),
        Expanded(
          child: _StatCard(
            icon: Icons.shield_rounded,
            iconColor: colors.info,
            label: context.l10n.grace,
            value: '${status.streakGraceRemaining}',
            suffix: 'left',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.suffix,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return CoolCard(
      variant: CoolCardVariant.glass,
      padding: EdgeInsets.all(space.x3),
      borderRadius: radii.sm,
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          SizedBox(height: space.x1),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          Text(
            suffix,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiaryText,
              fontSize: 10,
            ),
          ),
          SizedBox(height: space.x1),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaysToEarnGrid extends ConsumerWidget {
  const _WaysToEarnGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final activitiesAsync = ref.watch(coolActivitiesProvider);

    return activitiesAsync.when(
      data: (activities) {
        if (activities.isEmpty) {
          return const CoolEmptyView(
            message: 'No activities available right now',
            icon: Icons.auto_awesome_outlined,
            compact: true,
          );
        }

        // Group by category
        final grouped = <String, List<CoolActivity>>{};
        for (final a in activities) {
          grouped.putIfAbsent(a.category, () => []).add(a);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in grouped.entries) ...[
              Padding(
                padding: EdgeInsets.only(top: space.x3, bottom: space.x1),
                child: Text(
                  _categoryLabel(entry.key),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.tertiaryText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              CoolCard(
                child: Column(
                  children: [
                    for (int i = 0; i < entry.value.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: colors.border),
                      _EarnRow(activity: entry.value[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 4),
      error: (_, _) => const CoolEmptyView(
        message: 'Could not load activities',
        icon: Icons.error_outline_rounded,
        compact: true,
      ),
    );
  }

  static String _categoryLabel(String category) => switch (category) {
    'groups' => '💰 GROUPS',
    'rayon' => '⚽ RAYON SPORT',
    'social' => '📲 SOCIAL',
    'general' => '⭐ GENERAL',
    _ => category.toUpperCase(),
  };
}

class _EarnRow extends StatelessWidget {
  const _EarnRow({required this.activity});

  final CoolActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.x2),
      child: Row(
        children: [
          Text(activity.emoji, style: const TextStyle(fontSize: 20)),
          SizedBox(width: space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                if (activity.description.isNotEmpty)
                  Text(
                    activity.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.tertiaryText,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x2,
              vertical: space.x1,
            ),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(radii.md),
            ),
            child: Text(
              '+${activity.tokensAwarded} Points',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active missions section ───────────────────────────────────────

class _ActiveMissionsSection extends ConsumerWidget {
  const _ActiveMissionsSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) {
      return const CoolEmptyView(
        message: 'Sign in to see missions',
        icon: Icons.flag_outlined,
        compact: true,
      );
    }

    final space = context.coolSpace;
    final missionsAsync = ref.watch(activeMissionsProvider(userId));

    return missionsAsync.when(
      data: (missions) {
        if (missions.isEmpty) {
          return const CoolEmptyView(
            message: 'No active missions right now',
            icon: Icons.flag_outlined,
            compact: true,
          );
        }
        // Show up to 3 missions
        final shown = missions.take(3).toList();
        return Column(
          children: [
            for (int i = 0; i < shown.length; i++) ...[
              if (i > 0) SizedBox(height: space.x2),
              MissionProgressCard(mission: shown[i]),
            ],
          ],
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 2),
      error: (_, _) => const CoolEmptyView(
        message: 'Could not load missions',
        icon: Icons.error_outline_rounded,
        compact: true,
      ),
    );
  }
}

// ─── Top earners section ───────────────────────────────────────────

class _TopEarnersSection extends ConsumerWidget {
  const _TopEarnersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(topEarnersProvider);
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return leaderboardAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return const CoolEmptyView(
            message: 'Leaderboard is empty — be the first!',
            icon: Icons.leaderboard_rounded,
            compact: true,
          );
        }
        return CoolCard(
          child: Column(
            children: [
              ListTile(
                title: Text(context.l10n.str14DaysStreak),
                subtitle: Text(context.l10n.str50Tokens),
                trailing: TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: colors.appBackground,
                      builder: (context) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: CoolEmptyView(
                          message: 'No transaction history found',
                          icon: Icons.history_rounded,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    'View History',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
              for (int i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.border),
                _LeaderboardRow(entry: entries[i]),
              ],
            ],
          ),
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 5),
      error: (_, _) => const CoolEmptyView(
        message: 'Could not load leaderboard',
        icon: Icons.error_outline_rounded,
        compact: true,
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final isTopThree = entry.rank <= 3;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: space.x2),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTopThree
                  ? _rankColor(entry.rank).withValues(alpha: 0.16)
                  : colors.cardSurface,
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isTopThree
                    ? _rankColor(entry.rank)
                    : colors.secondaryText,
              ),
            ),
          ),
          SizedBox(width: space.x3),
          // Tier dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.tier.color,
            ),
          ),
          SizedBox(width: space.x2),
          // Name
          Expanded(
            child: Text(
              entry.displayName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Points
          Text(
            '${entry.totalPoints} Points',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
        ],
      ),
    );
  }

  static Color _rankColor(int rank) => switch (rank) {
    1 => const Color(0xFFFFD700), // gold
    2 => const Color(0xFFC0C0C0), // silver
    3 => const Color(0xFFCD7F32), // bronze
    _ => const Color(0xFF8C8C8C), // fallback grey
  };
}

// ─── Rewards marketplace ──────────────────────────────────────────

class _RewardsMarketplace extends ConsumerWidget {
  const _RewardsMarketplace({
    required this.userId,
    required this.currentPoints,
  });

  final String userId;
  final int currentPoints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = context.coolSpace;
    final rewardsAsync = ref.watch(availableRewardsProvider);

    return rewardsAsync.when(
      data: (rewards) {
        if (rewards.isEmpty) {
          return const CoolEmptyView(
            message: 'No rewards available right now',
            icon: Icons.redeem_outlined,
            compact: true,
          );
        }
        return Column(
          children: [
            for (final reward in rewards) ...[
              _RewardItem(
                reward: reward,
                canAfford: currentPoints >= reward.tokenCost,
                onRedeem: () => _handleRedeem(context, ref, reward),
              ),
              SizedBox(height: space.x2),
            ],
          ],
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 2),
      error: (_, _) => const CoolEmptyView(
        message: 'Could not load rewards',
        icon: Icons.error_outline_rounded,
        compact: true,
      ),
    );
  }

  Future<void> _handleRedeem(
    BuildContext context,
    WidgetRef ref,
    CoolReward reward,
  ) async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.elevatedBackground,
        title: Text(
          'Redeem ${reward.title}?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This will cost ${reward.tokenCost} points.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: colors.tertiaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Redeem',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(coolStatusProvider.notifier)
          .redeemReward(userId: userId, rewardId: reward.id);
      if (context.mounted) {
        if (success) {
          CoolToast.info(context, 'Reward redeemed successfully!');
        } else {
          CoolToast.info(context, 'Failed to redeem reward.');
        }
      }
    }
  }
}

class _RewardItem extends StatelessWidget {
  const _RewardItem({
    required this.reward,
    required this.canAfford,
    required this.onRedeem,
  });

  final CoolReward reward;
  final bool canAfford;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return CoolCard(
      variant: CoolCardVariant.glass,
      onTap: canAfford ? onRedeem : null,
      padding: EdgeInsets.all(space.x4),
      borderRadius: radii.lg,
      child: Row(
        children: [
          Text(reward.emoji, style: const TextStyle(fontSize: 24)),
          SizedBox(width: space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  reward.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: space.x3),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x2,
              vertical: space.x1,
            ),
            decoration: BoxDecoration(
              color: canAfford
                  ? colors.accent.withValues(alpha: 0.12)
                  : colors.border,
              borderRadius: BorderRadius.circular(radii.sm),
            ),
            child: Text(
              '${reward.tokenCost} Points',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: canAfford ? colors.accent : colors.tertiaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: colors.secondaryText),
        SizedBox(width: space.x2),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
