import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/status/models/cool_season.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';

/// Home screen banner showing the active season: theme, countdown, and reward preview.
class SeasonBanner extends StatelessWidget {
  const SeasonBanner({required this.season, this.seasonPoints = 0, super.key});

  final CoolSeason season;
  final int seasonPoints;

  @override
  Widget build(BuildContext context) {
    if (!season.isLive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.12),
            AppColors.blue.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ────────────────────────────────────
          Row(
            children: [
              Icon(IconMapper.from(season.emoji), size: 22, color: AppColors.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  season.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  season.timeRemainingLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ─── Season progress bar ───────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: season.progressThroughSeason,
              minHeight: 4,
              backgroundColor: AppColors.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.accent.withValues(alpha: 0.6),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ─── Footer: season points + reward preview ────
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 14, color: AppColors.text2),
                  const SizedBox(width: 4),
                  Text(
                    '$seasonPoints season pts',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (season.rewardsDescription != null)
                Text(
                  season.rewardsDescription!,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
