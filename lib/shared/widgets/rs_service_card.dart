import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import 'cool_card.dart';

class RsServiceCard extends StatelessWidget {
  const RsServiceCard({
    required this.icon,
    required this.name,
    required this.desc,
    required this.count,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String name;
  final String desc;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '$name. $desc. $count.',
      excludeSemantics: true,
      child: CoolCard(
        onTap: onTap,
        gradient: RsColors.rsHeroGradient,
        borderColor: RsColors.rsBlueBorder,
        child: Padding(
          padding: EdgeInsets.all(space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                icon,
                style: text.rayonCondensed(
                  theme.textTheme.titleLarge,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: space.x3),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.rayonCondensed(
                  theme.textTheme.titleLarge,
                  fontWeight: FontWeight.w900,
                  color: RsColors.rsWhite,
                  height: 0.95,
                ),
              ),
              SizedBox(height: space.x1 + 2),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: RsColors.rsWhite.withValues(alpha: 0.82),
                  height: 1.3,
                ),
              ),
              SizedBox(height: space.x3),
              Text(
                count,
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsGoldLight,
                ),
              ),
              SizedBox(height: space.x2),
              Text(
                'Open service',
                style: text.rayon(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
