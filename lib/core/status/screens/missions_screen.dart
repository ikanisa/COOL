import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/core_app_scaffold.dart';

/// Rewards activities screen — seasonal events and reward-earning activities.
class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoreAppScaffold(
      titleWidget: Row(
        children: [
          Text(
            'REWARD ',
            style: text.rayonCondensed(
              const TextStyle(fontSize: 28),
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              letterSpacing: 0.8,
            ),
          ),
          Text(
            'ACTIVITIES',
            style: text.rayonCondensed(
              const TextStyle(fontSize: 28),
              fontWeight: FontWeight.w900,
              color: colors.success,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
      fallbackLocation: AppRoutes.rewards,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Subtitle ─────────────────────────────────────────────
          Text(
            'TRACK SEASONAL EVENTS AND COMPLETE ACTIVITIES TO EARN FAN REWARDS.',
            style: text.mono(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              letterSpacing: 0.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CoolSpace.x7),

          // ─── Active Seasons ───────────────────────────────────────
          const _SectionHeader(
            icon: Icons.radio_button_checked,
            label: 'ACTIVE REWARD SEASONS',
          ),
          const SizedBox(height: CoolSpace.x4),
          _SeasonCard(
            emoji: '🚀',
            title: 'MARCH MADNESS',
            dateRange: '01 MAR — 31 MAR',
            badge: 'LIVE',
            badgeColor: colors.success,
            progress: 0.65,
            daysLeft: '8 days left',
            description:
                'End-of-month blitz — complete all daily activities for a 2x multiplier.',
          ),
          const SizedBox(height: CoolSpace.x3),
          _SeasonCard(
            emoji: '🌾',
            title: 'HARVEST SEASON',
            dateRange: '01 APR — 30 APR',
            badge: 'UPCOMING',
            badgeColor: colors.warning,
            progress: 0,
            daysLeft: '',
            description:
                'Collect points through community events and group activities.',
          ),
          const SizedBox(height: CoolSpace.x7),

          // ─── Earn Points ──────────────────────────────────────────
          const _SectionHeader(
            icon: Icons.star_outline_rounded,
            label: 'EARN POINTS',
          ),
          const SizedBox(height: CoolSpace.x4),

          // FAN CLUB category
          const _CategoryHeader(emoji: '⚙️', label: 'FAN CLUB'),
          const SizedBox(height: CoolSpace.x3),
          const _ActionTile(
            emoji: '📋',
            title: 'REGISTER',
            subtitle: 'Create fan membership',
            reward: 500,
          ),
          const SizedBox(height: CoolSpace.x2),
          const _ActionTile(
            emoji: '📊',
            title: 'COMPLETE PROFILE',
            subtitle: 'Fill all membership details',
            reward: 200,
          ),
          const SizedBox(height: CoolSpace.x4),

          // CONTRIBUTIONS category
          const _CategoryHeader(emoji: '💰', label: 'CONTRIBUTIONS'),
          const SizedBox(height: CoolSpace.x3),
          const _ActionTile(
            emoji: '🏗️',
            title: 'SUPPORT INITIATIVE',
            subtitle: 'Contribute to club causes',
            reward: 300,
          ),
          const SizedBox(height: CoolSpace.x2),
          const _ActionTile(
            emoji: '🎫',
            title: 'ATTEND MATCH',
            subtitle: 'Purchase and use tickets',
            reward: 150,
          ),
          const SizedBox(height: CoolSpace.x4),

          // SOCIAL category
          const _CategoryHeader(emoji: '🏥', label: 'SOCIAL'),
          const SizedBox(height: CoolSpace.x3),
          const _ActionTile(
            emoji: '👥',
            title: 'INVITE FRIEND',
            subtitle: 'Refer a new fan member',
            reward: 250,
          ),
          const SizedBox(height: CoolSpace.x2),
          const _ActionTile(
            emoji: '📣',
            title: 'SHARE GAME',
            subtitle: 'Share match on social media',
            reward: 100,
          ),
          const SizedBox(height: CoolSpace.x4),

          // GENERAL category
          const _CategoryHeader(emoji: '⭐', label: 'GENERAL'),
          const SizedBox(height: CoolSpace.x3),
          const _ActionTile(
            emoji: '📅',
            title: 'DAILY CHECK-IN',
            subtitle: 'Open app daily',
            reward: 50,
          ),
          const SizedBox(height: CoolSpace.x2),
          const _ActionTile(
            emoji: '🛍️',
            title: 'SHOP PURCHASE',
            subtitle: 'Buy from Gikundiro Shop',
            reward: 200,
          ),
        ],
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, color: colors.secondaryText, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: text.mono(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// ─── Category header ──────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(
          label,
          style: text.rayonCondensed(
            theme.textTheme.titleSmall,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─── Season card ──────────────────────────────────────────────────────────

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.emoji,
    required this.title,
    required this.dateRange,
    required this.badge,
    required this.badgeColor,
    required this.progress,
    required this.daysLeft,
    required this.description,
  });

  final String emoji;
  final String title;
  final String dateRange;
  final String badge;
  final Color badgeColor;
  final double progress;
  final String daysLeft;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: text.rayonCondensed(
                            theme.textTheme.titleMedium,
                            fontWeight: FontWeight.w900,
                            color: colors.primaryText,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(CoolRadii.pill),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            badge,
                            style: text.mono(
                              theme.textTheme.labelSmall,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateRange,
                      style: text.mono(
                        theme.textTheme.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress > 0) ...[
            const SizedBox(height: CoolSpace.x3),
            ClipRRect(
              borderRadius: BorderRadius.circular(CoolRadii.pill),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colors.cardSurface,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  RsColors.rsNavyLight,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                daysLeft,
                style: text.mono(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x3),
          Text(
            description,
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action tile ──────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.reward,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final int reward;

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
          // Emoji icon box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.rayonCondensed(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          // Star reward
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                color: RsColors.rsGoldLight,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '$reward',
                style: text.mono(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsGoldLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
