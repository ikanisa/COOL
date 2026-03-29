
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/rayon/models/rs_models.dart';
import '../../features/rayon/theme/rs_theme.dart' as rs_theme;

/// Initiative card matching the Support Club design:
///
/// ┌──────────────────────────────────┐
/// │  ┌────────────────────────────┐  │
/// │  │  [CATEGORY badge]          │  │  ← image with rounded corners
/// │  │         landscape image    │  │
/// │  └────────────────────────────┘  │
/// │  TITLE (condensed bold)          │
/// │  Description text (2 lines)…     │
/// │  4,800,000 RWF RAISED      96%  │
/// │  ████████████████████████████    │  ← blue progress bar
/// │  👥 850 SUPPORTERS   SUPPORT →  │
/// └──────────────────────────────────┘
class RsInitiativeCard extends StatelessWidget {
  const RsInitiativeCard({
    required this.initiative,
    required this.onSupportTap,
    this.onTap,
    super.key,
  });

  final RsInitiative initiative;
  final VoidCallback onSupportTap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final category = rs_theme.RsTheme.parseCategory(
      initiative.category.value.toLowerCase(),
    );
    final categoryColor = rs_theme.RsTheme.categoryColor(category);
    final progress = initiative.progress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();

    return Semantics(
      label:
          '${initiative.title}.'
          '$percent% funded. '
          '${initiative.supporterCount} supporters.',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CoolRadii.lg),
          child: Ink(
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Image area with category badge ─────────────────
                _ImageArea(
                  initiative: initiative,
                  category: category,
                  categoryColor: categoryColor,
                ),

                // ─── Text + metrics ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        initiative.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayonCondensed(
                          theme.textTheme.headlineSmall,
                          fontWeight: FontWeight.w900,
                          color: colors.primaryText,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Description
                      Text(
                        initiative.description.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayon(
                          theme.textTheme.bodySmall,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: colors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amount raised + percentage
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_formatAmount(initiative.raisedAmount)} RWF RAISED',
                              style: text.mono(
                                theme.textTheme.labelSmall,
                                fontWeight: FontWeight.w700,
                                color: colors.primaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            '$percent%',
                            style: text.mono(
                              theme.textTheme.labelMedium,
                              fontWeight: FontWeight.w800,
                              color: RsColors.rsNavyLight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(CoolRadii.pill),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.overlaySurface,
                                ),
                                child: const SizedBox.expand(),
                              ),
                              FractionallySizedBox(
                                widthFactor: progress,
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        RsColors.rsRed,
                                        RsColors.rsNavyLight,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Supporters count + SUPPORT → CTA
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 18,
                            color: colors.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} SUPPORTERS',
                              style: text.mono(
                                theme.textTheme.labelSmall,
                                fontWeight: FontWeight.w600,
                                color: colors.secondaryText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: onSupportTap,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'SUPPORT',
                                  style: text.rayonCondensed(
                                    theme.textTheme.labelLarge,
                                    fontWeight: FontWeight.w800,
                                    color: RsColors.rsNavyLight,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: RsColors.rsNavyLight,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Image area with category badge overlay ─────────────────────────────

class _ImageArea extends StatelessWidget {
  const _ImageArea({
    required this.initiative,
    required this.category,
    required this.categoryColor,
  });

  final RsInitiative initiative;
  final rs_theme.InitiativeCategory category;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);

    // Generate a deterministic gradient based on initiative title hash
    final hash = initiative.title.hashCode.abs();
    final hue = (hash % 360).toDouble();
    final bgColor1 = HSLColor.fromAHSL(1.0, hue, 0.25, 0.25).toColor();
    final bgColor2 =
        HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.3, 0.2).toColor();

    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgColor1, bgColor2],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.md),
      ),
      child: Stack(
        children: [
          // Decorative landscape icon overlay
          Positioned(
            right: 12,
            bottom: 12,
            child: Icon(
              _categoryIcon(category),
              size: 48,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),

          // Category badge (top-left)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: rs_theme.RsTheme.categoryBackground(category),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                border: Border.all(
                  color: categoryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                initiative.category.value.toUpperCase(),
                style: text.rayon(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: categoryColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(rs_theme.InitiativeCategory cat) {
    return switch (cat) {
      rs_theme.InitiativeCategory.infrastructure => Icons.stadium_rounded,
      rs_theme.InitiativeCategory.youth => Icons.sports_soccer_rounded,
      rs_theme.InitiativeCategory.community => Icons.groups_rounded,
      _ => Icons.favorite_rounded,
    };
  }
}

// ─── Formatting ───────────────────────────────────────────────────────────

String _formatAmount(int amount) {
  return NumberFormat.decimalPattern('en').format(amount);
}
