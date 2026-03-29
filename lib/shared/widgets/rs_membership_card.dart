import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/rayon/models/rs_models.dart';
import 'cool_card.dart';
import 'rs_tier_badge.dart';

class RsMembershipCard extends StatelessWidget {
  const RsMembershipCard({
    required this.membership,
    this.showPoints = true,
    super.key,
  });

  final RsFanMembership membership;
  final bool showPoints;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Semantics(
      label:
          'Rayon Sports membership. ${membership.displayName}.'
          '${membership.tier.label} tier. '
          '${showPoints ? '${membership.points} points.' : ''}',
      excludeSemantics: true,
      child: CoolCard(
        gradient: RsColors.rsMembershipGradient,
        borderColor: RsColors.rsRedBorder,
        borderRadius: radii.lg,
        padding: EdgeInsets.all(space.x5 + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAYON SPORTS FC',
                        style: text.rayonCondensed(
                          theme.textTheme.headlineSmall,
                          fontWeight: FontWeight.w900,
                          color: RsColors.rsWhite,
                          letterSpacing: 0.4,
                        ),
                      ),
                      SizedBox(height: space.x1 + 2),
                      Text(
                        membership.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayon(
                          theme.textTheme.titleSmall,
                          fontWeight: FontWeight.w700,
                          color: RsColors.rsWhite,
                        ),
                      ),
                      SizedBox(height: space.x1 / 2),
                      Text(
                        membership.chapter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayon(
                          theme.textTheme.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: RsColors.rsWhite.withValues(alpha: 0.74),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: space.x3),
                RsTierBadge(tier: membership.tier),
              ],
            ),
            SizedBox(height: space.x4),
            Row(
              children: [
                _RsMetric(
                  label: context.l10n.memberId,
                  value: membership.membershipNumber,
                ),
                SizedBox(width: space.x3),
                if (showPoints)
                  _RsMetric(
                    label: context.l10n.points2,
                    value: '${membership.points}',
                    accentColor: RsColors.rsGoldLight,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RsMetric extends StatelessWidget {
  const _RsMetric({
    required this.label,
    required this.value,
    this.accentColor = RsColors.rsWhite,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: EdgeInsets.all(space.x3 + 2),
        decoration: BoxDecoration(
          color: colors.overlaySurface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(radii.sm),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.rayon(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w600,
                color: RsColors.rsWhite.withValues(alpha: 0.72),
              ),
            ),
            SizedBox(height: space.x1 + 2),
            Text(
              value,
              style: text.mono(
                theme.textTheme.labelLarge,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
