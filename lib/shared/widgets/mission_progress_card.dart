import 'package:flutter/material.dart';

import '../../core/status/models/cool_mission.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/utils/icon_mapper.dart';
import 'cool_card.dart';

/// A compact card showing mission progress, countdown, and reward.
///
/// Designed for use in lists and the missions screen.
class MissionProgressCard extends StatelessWidget {
  const MissionProgressCard({required this.mission, this.onTap, super.key});

  final CoolMission mission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final progress = mission.progressPercent;
    final isCompleted = mission.isCompleted;

    return Semantics(
      button: onTap != null,
      label: mission.title,
      hint: onTap != null ? 'Opens mission details' : null,
      child: CoolCard(
        onTap: onTap,
        padding: const EdgeInsets.all(CoolSpace.x4),
        backgroundColor: isCompleted
            ? colors.chipSelectedBackground
            : colors.operationalSurface,
        borderColor: isCompleted
            ? colors.accent.withValues(alpha: 0.34)
            : colors.border,
        borderRadius: radii.sm,
        semanticsLabel: mission.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  IconMapper.from(mission.emoji),
                  size: 24,
                  color: colors.secondaryText,
                ),
                SizedBox(width: space.x3 - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mission.title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mission.description != null) ...[
                        SizedBox(height: space.x1 / 2),
                        Text(
                          mission.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.tertiaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: space.x2),
                _TimePill(label: mission.timeRemainingLabel),
              ],
            ),
            SizedBox(height: space.x3 + 2),
            Semantics(
              label:
                  'Mission progress ${(progress * 100).toStringAsFixed(0)} percent',
              child: ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.xs / 2),
                ),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.cardSurfaceStrong,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCompleted ? colors.accent : colors.info,
                  ),
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Row(
              children: [
                Text(
                  isCompleted
                      ? 'Completed'
                      : '${(progress * 100).toStringAsFixed(0)}% complete',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCompleted ? colors.accent : colors.secondaryText,
                  ),
                ),
                const Spacer(),
                if (mission.rewardPoints > 0)
                  Semantics(
                    label: '${mission.rewardPoints} reward points',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CoolSpace.x2,
                        vertical: CoolSpace.x1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.15),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.pill),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 12,
                            color: colors.warning,
                          ),
                          SizedBox(width: space.x1),
                          Text(
                            '${mission.rewardPoints} Points',
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.warning,
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
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Time remaining: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.cardSurfaceStrong,
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        ),
        child: Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.tertiaryText,
          ),
        ),
      ),
    );
  }
}
