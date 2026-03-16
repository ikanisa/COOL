import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_status_card.dart';
import '../../../shared/widgets/mission_progress_card.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/partners/rayon/models/rs_models.dart';
import '../models/cool_event.dart';
import '../models/cool_leaderboard_entry.dart';
import '../providers/cool_leaderboard_provider.dart';
import '../providers/cool_missions_provider.dart';
import '../providers/cool_status_provider.dart';

/// Full-page gamification hub for Cool Tokens.
class CoolTokensScreen extends ConsumerWidget {
  const CoolTokensScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final userId = ref.watch(authProvider).user?.id ?? '';
    final status = ref.watch(coolStatusProvider).valueOrNull;

    return Scaffold(
      backgroundColor: palette.bg,
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
                      context.go(AppRoutes.profile);
                    }
                  },
                  icon: Icon(Icons.arrow_back_rounded, color: palette.text),
                ),
                title: Text(
                  'Cool Tokens',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                centerTitle: false,
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── 1. Hero Card (tier + points + progress) ──
                    if (status != null) ...[
                      CoolStatusCard(status: status),
                      const SizedBox(height: 20),
                    ],

                    // ── 2. Streak & Stats ─────────────────────
                    if (status != null) ...[
                      _StreakStatsRow(status: status),
                      const SizedBox(height: 24),
                    ],

                    // ── 3. Ways to Earn ───────────────────────
                    _SectionHeader(
                      label: 'Ways to Earn',
                      icon: Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 10),
                    const _WaysToEarnGrid(),
                    const SizedBox(height: 24),

                    // ── 4. Active Missions ────────────────────
                    _SectionHeader(
                      label: 'Active Missions',
                      icon: Icons.flag_rounded,
                      trailing: TextButton(
                        onPressed: () => context.push(AppRoutes.missions),
                        child: Text(
                          'View all',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ActiveMissionsSection(userId: userId),
                    const SizedBox(height: 24),

                    // ── 5. Top Earners ────────────────────────
                    _SectionHeader(
                      label: 'Top Earners',
                      icon: Icons.leaderboard_rounded,
                    ),
                    const SizedBox(height: 10),
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
    final palette = context.coolPalette;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.orange,
            label: 'Current Streak',
            value: '${status.currentStreak}',
            suffix: 'days',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            iconColor: AppColors.yellow,
            label: 'Best Streak',
            value: '${status.longestStreak}',
            suffix: 'days',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.shield_rounded,
            iconColor: palette.blue,
            label: 'Grace',
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
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          Text(
            suffix,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: palette.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ways to earn grid ─────────────────────────────────────────────

class _WaysToEarnGrid extends StatelessWidget {
  const _WaysToEarnGrid();

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final events = CoolEventType.values;

    return CoolCard(
      child: Column(
        children: [
          for (int i = 0; i < events.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: palette.border),
            _EarnRow(eventType: events[i]),
          ],
        ],
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  const _EarnRow({required this.eventType});

  final CoolEventType eventType;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            eventType.emoji,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              eventType.displayLabel,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+${eventType.defaultPoints} pts',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.accent,
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
              if (i > 0) const SizedBox(height: 10),
              MissionProgressCard(mission: shown[i]),
            ],
          ],
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 2),
      error: (_, __) => const CoolEmptyView(
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
    final palette = context.coolPalette;

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
              for (int i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: palette.border),
                _LeaderboardRow(entry: entries[i]),
              ],
            ],
          ),
        );
      },
      loading: () => const CoolSkeletonList(itemCount: 5),
      error: (_, __) => const CoolEmptyView(
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
    final palette = context.coolPalette;
    final isTopThree = entry.rank <= 3;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                  : palette.surface2,
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isTopThree ? _rankColor(entry.rank) : palette.text2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Tier dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.tier.color,
            ),
          ),
          const SizedBox(width: 8),
          // Name
          Expanded(
            child: Text(
              entry.displayName,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Points
          Text(
            '${entry.totalPoints} pts',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.accent,
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
    _ => AppColors.text2,
  };
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
    final palette = context.coolPalette;
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.text2),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
