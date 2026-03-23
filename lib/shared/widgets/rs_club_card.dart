import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import 'cool_card.dart';

class RsClubCard extends StatelessWidget {
  const RsClubCard({
    required this.club,
    required this.joined,
    required this.onTap,
    super.key,
  });

  final RsFanClub club;
  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label:
          '${club.name}. ${club.region}.'
          '${joined ? 'Joined' : 'Not joined'}. '
          '${club.memberCount} members.',
      excludeSemantics: true,
      child: CoolCard(
        onTap: onTap,
        gradient: RsColors.rsCardGradient,
        borderColor: joined
            ? RsColors.rsGold.withValues(alpha: 0.55)
            : RsColors.rsBlueBorder,
        borderRadius: radii.lg,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      club.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.rayonCondensed(
                        theme.textTheme.headlineSmall,
                        fontWeight: FontWeight.w900,
                        color: RsColors.rsWhite,
                        height: 0.95,
                      ),
                    ),
                  ),
                  if (joined)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: space.x2 + 2,
                        vertical: space.x1 + 2,
                      ),
                      decoration: BoxDecoration(
                        color: RsColors.rsGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(radii.pill),
                        border: Border.all(
                          color: RsColors.rsGold.withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        'JOINED',
                        style: text.rayonCondensed(
                          theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w900,
                          color: RsColors.rsGoldLight,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: space.x1 + 2),
              Text(
                club.region,
                style: text.rayon(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsBluePale,
                ),
              ),
              SizedBox(height: space.x2),
              Text(
                club.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                  height: 1.35,
                ),
              ),
              SizedBox(height: space.x3),
              Text(
                '${club.memberCount} members',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsGoldLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
