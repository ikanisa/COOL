import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../core/status/models/cool_mission.dart';
import '../../../core/utils/icon_mapper.dart';

/// A compact card showing mission progress, countdown, and reward.
///
/// Designed for use in lists and the missions screen.
class MissionProgressCard extends StatelessWidget {
  const MissionProgressCard({required this.mission, this.onTap, super.key});

  final CoolMission mission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final progress = mission.progressPercent;
    final isCompleted = mission.isCompleted;

    return Semantics(
      button: onTap != null,
      label: mission.title,
      hint: onTap != null ? 'Opens mission details' : null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isCompleted
                ? palette.accent.withValues(alpha: 0.08)
                : palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? palette.accent.withValues(alpha: 0.3)
                  : palette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header: emoji + title + countdown ─────────
              Row(
                children: [
                  Icon(
                    IconMapper.from(mission.emoji),
                    size: 24,
                    color: palette.text2,
                  ),
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
                            color: palette.text,
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
                              color: palette.text3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TimePill(label: mission.timeRemainingLabel, palette: palette),
                ],
              ),

              const SizedBox(height: 14),

              // ─── Progress bar ────────────────────────────────
              Semantics(
                label:
                    'Mission progress ${(progress * 100).toStringAsFixed(0)} percent',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: palette.surface3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCompleted ? palette.accent : palette.blue,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ─── Footer: progress label + reward ─────────────
              Row(
                children: [
                  Text(
                    isCompleted
                        ? 'Completed'
                        : '${(progress * 100).toStringAsFixed(0)}% complete',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCompleted ? palette.accent : palette.text2,
                    ),
                  ),
                  const Spacer(),
                  if (mission.rewardPoints > 0)
                    Semantics(
                      label: '${mission.rewardPoints} reward points',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.yellow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 12,
                              color: palette.yellow,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${mission.rewardPoints} Tokens',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: palette.yellow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.label, required this.palette});
  final String label;
  final CoolPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Time remaining: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface3,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: palette.text3,
          ),
        ),
      ),
    );
  }
}
