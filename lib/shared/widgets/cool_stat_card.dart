import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_card.dart';

/// A reusable summary card for displaying a primary metric.
///
/// Use for savings hero cards, group balance summaries, dashboard KPIs, etc.
///
/// ```dart
/// CoolStatCard(
///   kicker: 'SAVINGS',
///   value: '125,000 RWF',
///   subtitle: '+3,200 this month',
/// )
///
/// CoolStatCard.accent(
///   kicker: 'TOTAL BALANCE',
///   value: '125,000 RWF',
///   trailing: Icon(Icons.arrow_forward_rounded),
///   onTap: () => openWallet(),
/// )
/// ```
class CoolStatCard extends StatelessWidget {
  const CoolStatCard({
    required this.value,
    this.kicker,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.variant = CoolStatCardVariant.default_,
    super.key,
  });

  /// Accent variant — gradient background for hero-level stats.
  const CoolStatCard.accent({
    required this.value,
    this.kicker,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    super.key,
  }) : variant = CoolStatCardVariant.accent;

  /// Glass variant — frosted translucent surface.
  const CoolStatCard.glass({
    required this.value,
    this.kicker,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    super.key,
  }) : variant = CoolStatCardVariant.glass;

  /// Small uppercase label above the value (e.g., "SAVINGS BALANCE").
  final String? kicker;

  /// The primary metric value (e.g., "125,000 RWF").
  final String value;

  /// A short subtitle below the value (e.g., "+3,200 this month").
  final String? subtitle;

  /// Custom widget in the subtitle position (overrides [subtitle] text).
  final Widget? subtitleWidget;

  /// Trailing widget (e.g., arrow icon, action button).
  final Widget? trailing;

  /// Tap handler — makes the entire card tappable.
  final VoidCallback? onTap;

  /// Visual variant.
  final CoolStatCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isAccent = variant == CoolStatCardVariant.accent;

    final kickerColor = isAccent
        ? colors.accentForeground.withValues(alpha: 0.88)
        : colors.secondaryText;
    final valueColor = isAccent ? colors.accentForeground : colors.primaryText;
    final subtitleColor = isAccent
        ? colors.accentForeground.withValues(alpha: 0.72)
        : colors.secondaryText;

    return CoolCard(
      variant: _cardVariant,
      useGradient: isAccent,
      gradient: isAccent ? colors.heroGradient : null,
      borderColor: isAccent ? colors.accent.withValues(alpha: 0.18) : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kicker != null)
            Text(
              kicker!,
              style: text.mobiLabel(color: kickerColor),
            ),
          if (kicker != null) const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headline(
                    theme.textTheme.displayMedium,
                    color: valueColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CoolSpace.x3),
                trailing!,
              ],
            ],
          ),
          if (subtitleWidget != null || subtitle != null) ...[
            const SizedBox(height: CoolSpace.x3),
            subtitleWidget ??
                Text(
                  subtitle!,
                  style: text.mobiLabel(color: subtitleColor),
                ),
          ],
        ],
      ),
    );
  }

  CoolCardVariant get _cardVariant => switch (variant) {
    CoolStatCardVariant.accent => CoolCardVariant.accent,
    CoolStatCardVariant.glass => CoolCardVariant.glass,
    CoolStatCardVariant.default_ => CoolCardVariant.default_,
  };
}

/// Variants for [CoolStatCard].
enum CoolStatCardVariant { default_, accent, glass }
