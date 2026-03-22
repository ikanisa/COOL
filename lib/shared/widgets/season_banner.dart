import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/status/models/cool_season.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/icon_mapper.dart';

/// Home screen banner showing the active season: theme, countdown, and reward preview.
class SeasonBanner extends StatelessWidget {
  const SeasonBanner({required this.season, this.seasonPoints = 0, this.onTap, super.key});

  final CoolSeason season;
  final int seasonPoints;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    if (!season.isLive) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Semantics(
      label: 'Active season ${season.title}. Tap to view all seasons.',
      button: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.accent.withValues(alpha: 0.12),
              palette.blue.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ────────────────────────────────────
            Row(
              children: [
                Icon(
                  IconMapper.from(season.emoji),
                  size: 22,
                  color: palette.text2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    season.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Season time remaining ${season.timeRemainingLabel}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      season.timeRemainingLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ─── Season progress bar ───────────────────────
            Semantics(
              label:
                  'Season progress ${(season.progressThroughSeason * 100).round()} percent',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: season.progressThroughSeason,
                  minHeight: 4,
                  backgroundColor: palette.surface3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    palette.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ─── Footer: season points + reward preview ────
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
                          color: palette.text2,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$seasonPoints Tokens',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.text2,
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
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: palette.text3,
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
      ),
    );
  }
}
