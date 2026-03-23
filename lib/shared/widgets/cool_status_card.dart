import 'package:flutter/material.dart';

import '../../core/status/models/cool_status.dart';
import '../../core/theme/cool_foundations.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import 'cool_card.dart';

/// Compact status card showing unified COOL tier, points, streak,
/// and progress to the next tier.
///
/// Designed to sit on the profile screen.
class CoolStatusCard extends StatelessWidget {
  const CoolStatusCard({required this.status, super.key});

  final CoolStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final tier = status.tier;

    return Semantics(
      label:
          '${tier.label} member. ${status.totalPoints} points.'
          '${status.currentStreak} day streak.',
      excludeSemantics: true,
      child: CoolCard(
        padding: CoolSpace.denseSectionPadding,
        borderRadius: radii.md,
        borderColor: tier.color.withValues(alpha: 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tier.color.withValues(alpha: 0.18),
            tier.color.withValues(alpha: 0.06),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TierDot(tier: tier),
                SizedBox(width: space.x3 - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cool Tokens',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.tertiaryText,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: space.x1 / 2),
                      Text(
                        '${tier.label} Member',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x3,
                    vertical: CoolSpace.x1 + 2,
                  ),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.16),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                  ),
                  child: Text(
                    '${status.totalPoints} Tokens',
                    style: text.mono(
                      theme.textTheme.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: tier.color,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: space.x4),
            if (tier != FanTier.platinum) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.xs / 2),
                      ),
                      child: LinearProgressIndicator(
                        value: status.progressToNextTier,
                        minHeight: 6,
                        backgroundColor: colors.cardSurfaceStrong,
                        valueColor: AlwaysStoppedAnimation<Color>(tier.color),
                      ),
                    ),
                  ),
                  SizedBox(width: space.x3 - 2),
                  Text(
                    '${status.pointsToNextTier} to ${_nextTierLabel(tier)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
              SizedBox(height: space.x3 + 2),
            ],
            Wrap(
              spacing: space.x2,
              runSpacing: space.x2,
              children: [
                _StatPill(
                  icon: Icons.local_fire_department_rounded,
                  label: '${status.currentStreak} streak',
                ),
                _StatPill(
                  icon: Icons.emoji_events_rounded,
                  label: '${status.longestStreak} best',
                ),
                if (status.streakGraceRemaining > 0)
                  _StatPill(
                    icon: Icons.shield_rounded,
                    label: '${status.streakGraceRemaining} grace',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _nextTierLabel(FanTier tier) => switch (tier) {
    FanTier.blue => 'Silver',
    FanTier.silver => 'Gold',
    FanTier.gold => 'Platinum',
    FanTier.platinum => 'Max',
  };
}

class _TierDot extends StatelessWidget {
  const _TierDot({required this.tier});

  final FanTier tier;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [tier.color, tier.color.withValues(alpha: 0.3)],
        ),
        boxShadow: CoolShadows.floating(brightness, strength: 0.24),
      ),
      child: Center(
        child: Icon(_tierIcon(tier), size: 18, color: Colors.white),
      ),
    );
  }

  static IconData _tierIcon(FanTier tier) => switch (tier) {
    FanTier.blue => Icons.favorite_rounded,
    FanTier.silver => Icons.workspace_premium_rounded,
    FanTier.gold => Icons.emoji_events_rounded,
    FanTier.platinum => Icons.diamond_rounded,
  };
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.secondaryText),
          const SizedBox(width: 4),
          Text(
            label,
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
