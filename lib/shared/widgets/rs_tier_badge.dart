import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../features/rayon/models/rs_models.dart';

class RsTierBadge extends StatelessWidget {
  const RsTierBadge({required this.tier, super.key});

  final FanTier tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Semantics(
      label: '${tier.label} tier',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: space.x3,
          vertical: space.x1 + 3,
        ),
        decoration: BoxDecoration(
          color: tier.glowColor,
          borderRadius: BorderRadius.circular(radii.pill),
          border: Border.all(color: tier.color.withValues(alpha: 0.7)),
        ),
        child: Text(
          tier.label.toUpperCase(),
          style: text.rayonCondensed(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: tier == FanTier.bronze ? colors.primaryText : tier.color,
          ),
        ),
      ),
    );
  }
}
