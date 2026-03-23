import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../rs_membership_package.dart';
import '../widgets/rs_tier_badge.dart';
import '../../../../core/l10n/l10n.dart';

/// Full-screen page showing all Rayon Sports membership tiers with
/// benefits, point thresholds, and the user's current position.
class MembershipTiersScreen extends StatelessWidget {
  const MembershipTiersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Consumer(
      builder: (context, ref, _) {
        final colors = context.coolSemanticColors;
        final membershipAsync = ref.watch(rayonUserMembershipProvider);
        final packagesAsync = ref.watch(rayonMembershipPackagesProvider);

        return Scaffold(
          backgroundColor: colors.appBackground,
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
                  leading: buildPartnerBackButton(
                    context,
                    fallbackLocation: AppRoutes.rayonHome,
                  ),
                  title: Text(
                    'Membership Plans',
                    style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                  ),
                  actions: buildPartnerAppBarActions(context),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                  sliver: membershipAsync.when(
                    data: (membership) {
                      final currentTier = membership?.tier ?? FanTier.blue;
                      final currentPoints = membership?.points ?? 0;
                      return packagesAsync.when(
                        data: (packages) => _TierList(
                          currentTier: currentTier,
                          currentPoints: currentPoints,
                          packages: packages,
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
                        error: (_, _) => _TierList(
                          currentTier: currentTier,
                          currentPoints: currentPoints,
                          packages: const [],
                        ),
                      );
                    },
                    loading: () => SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: CoolSkeleton.card(),
                        ),
                        childCount: 4,
                      ),
                    ),
                    error: (error, stack) => SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'Could not load membership info',
                          style: GoogleFonts.dmSans(color: colors.tertiaryText),
                        ),
                      ),
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
    required this.packages,
  });

  final FanTier currentTier;
  final int currentPoints;
  final List<RsMembershipPackage> packages;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final sortedPackages = packages.toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));

    return SliverList(
      delegate: SliverChildListDelegate([
        // Introductory card
        _IntroCard(currentTier: currentTier, currentPoints: currentPoints),
        const SizedBox(height: CoolSpace.x5),

        // One card per tier, from Blue (lowest) to Platinum (highest)
        for (final package in sortedPackages) ...[
          _TierCard(
            package: package,
            isCurrent: package.tier == currentTier,
            isUnlocked: package.tier.index <= currentTier.index,
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
  const _IntroCard({required this.currentTier, required this.currentPoints});

  final FanTier currentTier;
  final int currentPoints;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final nextTier = currentTier.index < FanTier.values.length - 1
        ? FanTier.values[currentTier.index + 1]
        : null;

    return CoolCard(
      gradient: colors.surfaceGradient,
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RsTierBadge(tier: currentTier),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You are a ${currentTier.label}',
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 18),
                    fontWeight: FontWeight.w800,
                    color: RsColors.rsWhite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$currentPoints fan Tokens earned',
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
              'Top tier reached!',
              style: context.coolText.rayon(
                const TextStyle(fontSize: 13),
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                height: 1.45,
              ),
            ),
          ],
        ],
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
    final colors = context.coolSemanticColors;
    final floor = currentTier.minPoints;
    final ceiling = nextTier.minPoints;
    final span = ceiling - floor;
    final progress = span > 0
        ? ((currentPoints - floor) / span).clamp(0.0, 1.0)
        : 1.0;
    final remaining = (ceiling - currentPoints).clamp(0, ceiling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RsProgressBar(progress: progress, fillColor: nextTier.color, height: 8),
        const SizedBox(height: CoolSpace.x2),
        Text(
          '$remaining Tokens to ${nextTier.label}',
          style: context.coolText.rayon(
            const TextStyle(fontSize: 12),
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

// ── Individual tier card ──────────────────────────────────────────

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.package,
    required this.isCurrent,
    required this.isUnlocked,
    required this.currentPoints,
  });

  final RsMembershipPackage package;
  final bool isCurrent;
  final bool isUnlocked;
  final int currentPoints;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final tier = package.tier;

    return CoolCard(
      gradient: isCurrent
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tier.color.withValues(alpha: 0.18), colors.cardSurface],
            )
          : colors.surfaceGradient,
      borderColor: isCurrent
          ? tier.color.withValues(alpha: 0.5)
          : colors.border,
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
                  child: Icon(
                    _tierIcon(tier),
                    size: 22,
                    color: isUnlocked ? tier.color : colors.tertiaryText,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.title,
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 20),
                          fontWeight: FontWeight.w800,
                          color: isUnlocked
                              ? RsColors.rsWhite
                              : colors.tertiaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        package.subtitle,
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 12),
                          fontWeight: FontWeight.w500,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  _StatusChip(
                    label: context.l10n.current,
                    color: tier.color,
                    filled: true,
                  )
                else if (isUnlocked)
                  _StatusChip(
                    label: context.l10n.unlocked,
                    color: colors.accent,
                    filled: false,
                  )
                else
                  _StatusChip(
                    label: '${tier.minPoints} Tokens',
                    color: colors.tertiaryText,
                    filled: false,
                  ),
              ],
            ),

            const SizedBox(height: CoolSpace.x4),

            if (package.description.trim().isNotEmpty) ...[
              Text(
                package.description,
                style: context.coolText.rayon(
                  const TextStyle(fontSize: 12),
                  fontWeight: FontWeight.w500,
                  color: isUnlocked
                      ? colors.secondaryText
                      : colors.tertiaryText.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ── Benefits list ───────────────────────────────
            ...package.benefits.map(
              (benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _benefitIcon(benefit.title),
                      size: 16,
                      color: isUnlocked ? tier.color : colors.tertiaryText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit.title,
                            style: context.coolText.rayon(
                              const TextStyle(fontSize: 14),
                              fontWeight: FontWeight.w700,
                              color: isUnlocked
                                  ? RsColors.rsWhite
                                  : colors.tertiaryText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            benefit.description,
                            style: context.coolText.rayon(
                              const TextStyle(fontSize: 12),
                              fontWeight: FontWeight.w500,
                              color: isUnlocked
                                  ? colors.secondaryText
                                  : colors.tertiaryText.withValues(alpha: 0.6),
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
    final colors = context.coolSemanticColors;
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
          style: context.coolText.rayon(
            const TextStyle(fontSize: 11),
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

IconData _tierIcon(FanTier tier) => switch (tier) {
  FanTier.blue => Icons.favorite_rounded,
  FanTier.silver => Icons.workspace_premium_rounded,
  FanTier.gold => Icons.emoji_events_rounded,
  FanTier.platinum => Icons.diamond_rounded,
};

IconData _benefitIcon(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('ticket')) {
    return Icons.confirmation_number_rounded;
  }
  if (normalized.contains('shop') || normalized.contains('kit')) {
    return Icons.shopping_bag_rounded;
  }
  if (normalized.contains('meet') || normalized.contains('event')) {
    return Icons.auto_awesome_rounded;
  }
  if (normalized.contains('discount')) {
    return Icons.local_offer_rounded;
  }
  if (normalized.contains('badge')) {
    return Icons.military_tech_rounded;
  }
  return Icons.star_rounded;
}
