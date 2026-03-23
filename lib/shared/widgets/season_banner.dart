import 'package:flutter/material.dart';

import '../../core/status/models/cool_season.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/utils/icon_mapper.dart';
import 'cool_card.dart';

/// Home screen banner showing the active season: theme, countdown, and reward preview.
class SeasonBanner extends StatelessWidget {
  const SeasonBanner({
    required this.season,
    this.seasonPoints = 0,
    this.onTap,
    super.key,
  });

  final CoolSeason season;
  final int seasonPoints;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (!season.isLive) return const SizedBox.shrink();

    return Semantics(
      label: 'Active season ${season.title}. Tap to view all seasons.',
      button: onTap != null,
      child: CoolCard(
        onTap: onTap,
        padding: const EdgeInsets.all(CoolSpace.x4),
        borderRadius: CoolRadii.sm,
        borderColor: colors.accent.withValues(alpha: 0.2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.12),
            colors.info.withValues(alpha: 0.08),
          ],
        ),
        semanticsLabel: season.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  IconMapper.from(season.emoji),
                  size: 22,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    season.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Season time remaining ${season.timeRemainingLabel}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CoolSpace.x2,
                      vertical: CoolSpace.x1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.pill),
                      ),
                    ),
                    child: Text(
                      season.timeRemainingLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(
              label:
                  'Season progress ${(season.progressThroughSeason * 100).round()} percent',
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(
                  value: season.progressThroughSeason,
                  minHeight: 4,
                  backgroundColor: colors.cardSurfaceStrong,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Semantics(
                    label: '$seasonPoints season Tokens',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: colors.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$seasonPoints Tokens',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (season.rewardsDescription != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Semantics(
                      label: season.rewardsDescription!,
                      child: Text(
                        season.rewardsDescription!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
