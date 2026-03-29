import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/theme/rs_text_styles.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/rs_tier_badge.dart';
import '../models/rs_models.dart';
import '../models/rs_xp_models.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../core/status/providers/cool_leaderboard_provider.dart';
import '../widgets/partner_navigation.dart';

/// Gamification Hub — XP, Badges, and Leaderboard in one ROUGEBLACK screen.
///
/// Three-tab layout:
///   1. XP Overview — tier progress arc, XP event table, streaks
///   2. Badges — achievement grid
///   3. Leaderboard — top 20 fans ranked by total points
class GamificationScreen extends ConsumerStatefulWidget {
  const GamificationScreen({super.key});

  @override
  ConsumerState<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends ConsumerState<GamificationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            floating: true,
            expandedHeight: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: buildPartnerBackButton(
              context,
              fallbackLocation: AppRoutes.rayonHome,
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FAN ',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
                Text(
                  'EXPERIENCE',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsRed),
                ),
              ],
            ),
            actions: buildPartnerAppBarActions(context),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: RsColors.rsRed,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: RsColors.rsWhite,
              unselectedLabelColor: colors.tertiaryText,
              labelStyle: RsTextStyles.sectionTitle(
                color: RsColors.rsWhite,
              ).copyWith(fontSize: 13),
              tabs: const [
                Tab(text: 'XP'),
                Tab(text: 'BADGES'),
                Tab(text: 'RANKS'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: const [
            _XpOverviewTab(),
            _BadgesTab(),
            _LeaderboardTab(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1: XP OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════

class _XpOverviewTab extends ConsumerWidget {
  const _XpOverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final membershipAsync = ref.watch(rayonUserMembershipProvider);

    return membershipAsync.when(
      data: (membership) {
        final currentTier = membership?.tier ?? FanTier.fan;
        final currentPoints = membership?.points ?? 0;
        final nextTierPoints = membership?.nextTierPoints ?? 1000;
        final progress = membership?.progressToNextTier ?? 0.0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 96),
          children: [
            // ─── XP Progress Arc ─────────────────────────────────
            _XpProgressCard(
              tier: currentTier,
              points: currentPoints,
              nextTierPoints: nextTierPoints,
              progress: progress,
            ),
            const SizedBox(height: 24),

            // ─── Streak Counter ──────────────────────────────────
            const _StreakCard(),
            const SizedBox(height: 24),

            // ─── Ways to Earn XP ─────────────────────────────────
            _SectionLabel(
              icon: Icons.bolt_rounded,
              label: 'EARN XP',
              color: colors.secondaryText,
            ),
            const SizedBox(height: 12),
            ...XpEventType.values.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _XpEventTile(event: event),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: RsColors.rsRed),
      ),
      error: (_, _) => Center(
        child: Text(
          'Failed to load XP data',
          style: TextStyle(color: colors.secondaryText),
        ),
      ),
    );
  }
}

// ─── XP Progress Arc Card ─────────────────────────────────────────────────

class _XpProgressCard extends StatelessWidget {
  const _XpProgressCard({
    required this.tier,
    required this.points,
    required this.nextTierPoints,
    required this.progress,
  });

  final FanTier tier;
  final int points;
  final int nextTierPoints;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final pointsToGo = (nextTierPoints - points).clamp(0, nextTierPoints);

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: tier.color.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Arc
          SizedBox(
            width: 180,
            height: 110,
            child: CustomPaint(
              painter: _XpArcPainter(
                progress: progress,
                trackColor: colors.borderStrong,
                progressColor: tier.color,
                glowColor: tier.glowColor,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$points',
                        style: text.rayonCondensed(
                          const TextStyle(fontSize: 36),
                          fontWeight: FontWeight.w900,
                          color: tier.color,
                        ),
                      ),
                      Text(
                        'XP',
                        style: text.mono(
                          theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w800,
                          color: colors.tertiaryText,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Tier badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RsTierBadge(tier: tier),
              if (tier != FanTier.platinum) ...[
                const SizedBox(width: 12),
                Text(
                  '$pointsToGo XP to next tier',
                  style: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── XP Arc Painter ───────────────────────────────────────────────────────

class _XpArcPainter extends CustomPainter {
  _XpArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.glowColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    final radius = size.width / 2 - 12;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Progress glow
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress.clamp(0, 1),
      false,
      glowPaint,
    );

    // Progress fill
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _XpArcPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

// ─── Streak Card ──────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    // Placeholder streak data — will be driven by provider in future
    const currentStreak = 0;
    const longestStreak = 0;

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Row(
        children: [
          // Flame icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: RsColors.rsRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CoolRadii.sm),
            ),
            alignment: Alignment.center,
            child: const Text('🔥', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAILY STREAK',
                  style: text.rayonCondensed(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentStreak > 0
                      ? '$currentStreak day${currentStreak > 1 ? 's' : ''} active'
                      : 'Start your streak today!',
                  style: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currentStreak',
                style: text.rayonCondensed(
                  const TextStyle(fontSize: 28),
                  fontWeight: FontWeight.w900,
                  color: currentStreak > 0 ? RsColors.rsRed : colors.tertiaryText,
                ),
              ),
              if (longestStreak > 0)
                Text(
                  'Best: $longestStreak',
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── XP Event Tile ────────────────────────────────────────────────────────

class _XpEventTile extends StatelessWidget {
  const _XpEventTile({required this.event});

  final XpEventType event;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Row(
        children: [
          // Emoji box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Text(event.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          // Label + frequency
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label.toUpperCase(),
                  style: text.rayonCondensed(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.frequency,
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          // XP reward
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, color: RsColors.rsGold, size: 18),
              const SizedBox(width: 4),
              Text(
                '+${event.xpReward}',
                style: text.mono(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsGold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2: BADGES
// ═══════════════════════════════════════════════════════════════════════════

class _BadgesTab extends ConsumerWidget {
  const _BadgesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final membershipAsync = ref.watch(rayonUserMembershipProvider);

    return membershipAsync.when(
      data: (membership) {
        final userId = membership?.userId ?? '';
        if (userId.isEmpty) {
          return _emptyState(colors, 'Sign in to view your badges');
        }

        // Use the achievements provider if available, otherwise show
        // the static badge catalog grid
        return _BadgeCatalogGrid();
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: RsColors.rsRed),
      ),
      error: (_, _) => _emptyState(colors, 'Failed to load badges'),
    );
  }

  Widget _emptyState(CoolSemanticColors colors, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: colors.secondaryText, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Static badge catalog showing all available achievement types.
class _BadgeCatalogGrid extends StatelessWidget {
  // All badge types defined in the app
  static const _badgeTypes = [
    ('ticket-buyer', '🎫', 'Ticket Buyer', 'Purchase your first match ticket'),
    ('first-purchase', '🛍️', 'First Purchase', 'Make your first shop purchase'),
    ('supporter', '🤝', 'Club Supporter', 'Back a community initiative'),
    ('monthly-active', '📅', 'Monthly Active', 'Be active for a full calendar month'),
    ('top-recruiter', '📣', 'Top Recruiter', 'Recruit 5+ new fans'),
    ('match-attendance', '🏟️', 'Matchday Loyalist', 'Attend 10+ matches'),
    ('season-holder', '🎖️', 'Season Holder', 'Hold a full-season membership'),
    ('streak-7', '🔥', '7-Day Streak', 'Open the app 7 days in a row'),
    ('streak-30', '💎', '30-Day Streak', 'Open the app 30 days in a row'),
    ('gold-tier', '🏆', 'Gold Achiever', 'Reach Gold Fan tier'),
    ('platinum-tier', '👑', 'Legend', 'Reach Platinum Fan tier'),
    ('century-club', '💯', 'Century Club', 'Earn 10,000+ total XP'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _badgeTypes.length,
      itemBuilder: (context, index) {
        final (_, emoji, name, desc) = _badgeTypes[index];

        return GestureDetector(
          onLongPress: () {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(desc),
                backgroundColor: colors.cardSurfaceStrong,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
          child: Opacity(
            opacity: 0.4, // Locked state — will be 1.0 when provider marks earned
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.cardSurface,
                    border: Border.all(
                      color: colors.borderStrong,
                      width: 1.5,
                    ),
                    boxShadow: null,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 80,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.rayon(
                      theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3: LEADERBOARD
// ═══════════════════════════════════════════════════════════════════════════

class _LeaderboardTab extends ConsumerWidget {
  const _LeaderboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final leaderboardAsync = ref.watch(topEarnersProvider);

    return leaderboardAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏅', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'Leaderboard coming soon',
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to earn XP and claim the top spot!',
                  style: TextStyle(
                    color: colors.tertiaryText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 96),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final isTop3 = entry.rank <= 3;

            // Top 3 medal colors
            final medalEmoji = switch (entry.rank) {
              1 => '🥇',
              2 => '🥈',
              3 => '🥉',
              _ => null,
            };

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CoolCard(
                backgroundColor: isTop3
                    ? colors.cardSurfaceStrong
                    : colors.cardSurface,
                borderColor: isTop3
                    ? entry.tier.color.withValues(alpha: 0.3)
                    : colors.borderStrong,
                child: Row(
                  children: [
                    // Rank
                    SizedBox(
                      width: 36,
                      child: medalEmoji != null
                          ? Text(
                              medalEmoji,
                              style: const TextStyle(fontSize: 22),
                              textAlign: TextAlign.center,
                            )
                          : Text(
                              '#${entry.rank}',
                              textAlign: TextAlign.center,
                              style: text.mono(
                                theme.textTheme.bodyMedium,
                                fontWeight: FontWeight.w800,
                                color: colors.tertiaryText,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Avatar circle
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.tier.color.withValues(alpha: 0.15),
                        border: Border.all(
                          color: entry.tier.color.withValues(alpha: 0.5),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        entry.displayName.isNotEmpty
                            ? entry.displayName[0].toUpperCase()
                            : '?',
                        style: text.rayonCondensed(
                          theme.textTheme.titleMedium,
                          fontWeight: FontWeight.w900,
                          color: entry.tier.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + tier
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayName,
                            style: text.rayon(
                              theme.textTheme.bodyMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.tier.label,
                            style: text.mono(
                              theme.textTheme.labelSmall,
                              fontWeight: FontWeight.w600,
                              color: entry.tier.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Points
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatNumber(entry.totalPoints),
                          style: text.rayonCondensed(
                            theme.textTheme.titleMedium,
                            fontWeight: FontWeight.w900,
                            color: isTop3
                                ? RsColors.rsGold
                                : colors.primaryText,
                          ),
                        ),
                        Text(
                          'XP',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.tertiaryText,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: RsColors.rsRed),
      ),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Failed to load leaderboard',
              style: TextStyle(color: colors.secondaryText, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─── Shared: Section Label ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: text.mono(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
