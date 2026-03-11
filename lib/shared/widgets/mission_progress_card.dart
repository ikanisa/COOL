import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/status/models/cool_mission.dart';

/// A compact card showing mission progress, countdown, and reward.
///
/// Designed for use in lists and the missions screen.
class MissionProgressCard extends StatelessWidget {
  const MissionProgressCard({
    required this.mission,
    this.onTap,
    super.key,
  });

  final CoolMission mission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = mission.progressPercent;
    final isCompleted = mission.isCompleted;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCompleted
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCompleted
                ? AppColors.accent.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header: emoji + title + countdown ─────────
            Row(
              children: [
                Text(mission.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mission.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mission.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          mission.description!,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.text3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _TimePill(label: mission.timeRemainingLabel),
              ],
            ),

            const SizedBox(height: 14),

            // ─── Progress bar ────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.surface3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? AppColors.accent : AppColors.blue,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ─── Footer: progress label + reward ─────────────
            Row(
              children: [
                Text(
                  isCompleted
                      ? '✅ Completed'
                      : '${(progress * 100).toStringAsFixed(0)}% complete',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isCompleted ? AppColors.accent : AppColors.text2,
                  ),
                ),
                const Spacer(),
                if (mission.rewardPoints > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '🏆 ${mission.rewardPoints} pts',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.yellow,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.text3,
        ),
      ),
    );
  }
}
