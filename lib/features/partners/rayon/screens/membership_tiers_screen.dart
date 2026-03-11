import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../widgets/rs_tier_badge.dart';

/// Full-screen page showing all Rayon Sports membership tiers with
/// benefits, point thresholds, and the user's current position.
class MembershipTiersScreen extends StatelessWidget {
  const MembershipTiersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final membershipAsync = ref.watch(rayonUserMembershipProvider);

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CoolScreenBackground(
            primaryColor: RsColors.rsBlue,
            secondaryColor: RsColors.rsGold,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 0,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: IconButton(
                    onPressed: () => context.go('/partners/rayon-sports'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  title: Text(
                    'Membership Plans',
                    style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                  sliver: membershipAsync.when(
                    data: (membership) => _TierList(
                      currentTier: membership?.tier ?? FanTier.blue,
                      currentPoints: membership?.points ?? 0,
                    ),
                    loading: () => SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: CoolSkeleton.card(),
                        ),
                        childCount: 4,
                      ),
                    ),
                    error: (error, stack) => _TierList(
                      currentTier: FanTier.blue,
                      currentPoints: 0,
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

// ── Tier list ─────────────────────────────────────────────────────

class _TierList extends StatelessWidget {
  const _TierList({
    required this.currentTier,
    required this.currentPoints,
  });

  final FanTier currentTier;
  final int currentPoints;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        // Introductory card
        _IntroCard(currentTier: currentTier, currentPoints: currentPoints),
        const SizedBox(height: 20),

        // One card per tier, from Blue (lowest) to Platinum (highest)
        for (final tier in FanTier.values) ...[
          _TierCard(
            tier: tier,
            isCurrent: tier == currentTier,
            isUnlocked: tier.index <= currentTier.index,
            currentPoints: currentPoints,
          ),
          const SizedBox(height: 14),
        ],
      ]),
    );
  }
}

// ── Intro summary card ────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.currentTier,
    required this.currentPoints,
  });

  final FanTier currentTier;
  final int currentPoints;

  @override
  Widget build(BuildContext context) {
    final nextTier = currentTier.index < FanTier.values.length - 1
        ? FanTier.values[currentTier.index + 1]
        : null;

    return CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: RsColors.rsBlueBorder,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RsTierBadge(tier: currentTier),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You are a ${currentTier.label} Member',
                    style: GoogleFonts.barlow(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.rsWhite,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '$currentPoints fan points earned',
              style: GoogleFonts.dmMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: RsColors.rsGoldLight,
              ),
            ),
            if (nextTier != null) ...[
              const SizedBox(height: 14),
              _ProgressToNext(
                currentPoints: currentPoints,
                currentTier: currentTier,
                nextTier: nextTier,
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'You have reached the highest tier — enjoy all benefits!',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressToNext extends StatelessWidget {
  const _ProgressToNext({
    required this.currentPoints,
    required this.currentTier,
    required this.nextTier,
  });

  final int currentPoints;
  final FanTier currentTier;
  final FanTier nextTier;

  @override
  Widget build(BuildContext context) {
    final floor = currentTier.minPoints;
    final ceiling = nextTier.minPoints;
    final span = ceiling - floor;
    final progress =
        span > 0 ? ((currentPoints - floor) / span).clamp(0.0, 1.0) : 1.0;
    final remaining = (ceiling - currentPoints).clamp(0, ceiling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RsProgressBar(
          progress: progress,
          fillColor: nextTier.color,
          height: 8,
        ),
        const SizedBox(height: 8),
        Text(
          '$remaining pts to ${nextTier.label}',
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }
}

// ── Individual tier card ──────────────────────────────────────────

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.isCurrent,
    required this.isUnlocked,
    required this.currentPoints,
  });

  final FanTier tier;
  final bool isCurrent;
  final bool isUnlocked;
  final int currentPoints;

  @override
  Widget build(BuildContext context) {
    final meta = _tierMeta(tier);

    return CoolCard(
      gradient: isCurrent
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tier.color.withValues(alpha: 0.18),
                AppColors.surface2,
              ],
            )
          : AppColors.cardGradient,
      borderColor: isCurrent
          ? tier.color.withValues(alpha: 0.5)
          : AppColors.border,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tier.color.withValues(alpha: 0.35),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    meta.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.label,
                        style: GoogleFonts.barlow(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isUnlocked
                              ? AppColors.rsWhite
                              : AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.subtitle,
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  _StatusChip(
                    label: 'Current',
                    color: tier.color,
                    filled: true,
                  )
                else if (isUnlocked)
                  _StatusChip(
                    label: 'Unlocked',
                    color: AppColors.accent,
                    filled: false,
                  )
                else
                  _StatusChip(
                    label: '${tier.minPoints} pts',
                    color: AppColors.text3,
                    filled: false,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Benefits list ───────────────────────────────
            ...meta.benefits.map(
              (benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      benefit.emoji,
                      style: TextStyle(
                        fontSize: 16,
                        color: isUnlocked ? null : AppColors.text3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit.title,
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isUnlocked
                                  ? AppColors.rsWhite
                                  : AppColors.text3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            benefit.description,
                            style: GoogleFonts.barlow(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isUnlocked
                                  ? AppColors.text2
                                  : AppColors.text3.withValues(alpha: 0.6),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.filled,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── Tier metadata ─────────────────────────────────────────────────

class _TierMeta {
  const _TierMeta({
    required this.emoji,
    required this.subtitle,
    required this.benefits,
  });

  final String emoji;
  final String subtitle;
  final List<_Benefit> benefits;
}

class _Benefit {
  const _Benefit({
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;
}

_TierMeta _tierMeta(FanTier tier) {
  return switch (tier) {
    FanTier.blue => const _TierMeta(
        emoji: '💙',
        subtitle: 'Free — every fan starts here',
        benefits: [
          _Benefit(
            emoji: '🎫',
            title: 'Standard Tickets',
            description: 'Buy match tickets at regular pricing.',
          ),
          _Benefit(
            emoji: '🛍️',
            title: 'Club Shop Access',
            description: 'Browse and purchase official Rayon merch.',
          ),
          _Benefit(
            emoji: '📊',
            title: 'Fan Points',
            description:
                'Earn points from attendance, purchases, and support.',
          ),
        ],
      ),
    FanTier.silver => const _TierMeta(
        emoji: '🥈',
        subtitle: '1,000 pts — dedicated supporter',
        benefits: [
          _Benefit(
            emoji: '🎫',
            title: '5% Ticket Discount',
            description: 'Save on every match ticket purchase.',
          ),
          _Benefit(
            emoji: '⭐',
            title: 'Priority Queue',
            description: 'Jump the queue when tickets open for big matches.',
          ),
          _Benefit(
            emoji: '🏅',
            title: 'Silver Badge',
            description: 'Exclusive silver badge on your fan profile.',
          ),
        ],
      ),
    FanTier.gold => const _TierMeta(
        emoji: '🥇',
        subtitle: '2,000 pts — elite supporter',
        benefits: [
          _Benefit(
            emoji: '🎫',
            title: 'Priority Tickets',
            description: 'Get earlier access to on-sale match entries.',
          ),
          _Benefit(
            emoji: '🛍️',
            title: '10% Shop Discount',
            description: 'Unlock supporter pricing on official club gear.',
          ),
          _Benefit(
            emoji: '✨',
            title: 'VIP Events',
            description:
                'Access select fan sessions and special event queues.',
          ),
        ],
      ),
    FanTier.platinum => const _TierMeta(
        emoji: '💎',
        subtitle: '5,000 pts — ultimate fan',
        benefits: [
          _Benefit(
            emoji: '🎫',
            title: 'Priority Tickets + 15% Off',
            description: 'Best pricing and first access to all matches.',
          ),
          _Benefit(
            emoji: '🤝',
            title: 'Meet & Greet',
            description:
                'Join premium player and club meetups when available.',
          ),
          _Benefit(
            emoji: '👕',
            title: 'Free Kit',
            description:
                'Receive one complimentary official kit each season.',
          ),
          _Benefit(
            emoji: '🏆',
            title: 'All Gold Benefits',
            description:
                'VIP events, shop discounts, and everything from lower tiers.',
          ),
        ],
      ),
  };
}
