import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/rayon/models/rs_contribution_models.dart';
import 'rs_progress_bar.dart';

/// A premium card that displays a contribution group/circle summary.
///
/// Shows group name, type badge, progress bar, member count, and deadline.
class RsCircleCard extends StatelessWidget {
  const RsCircleCard({
    required this.group,
    this.onTap,
    super.key,
  });

  final RsContributionGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final fmt = NumberFormat.decimalPattern('en');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.cardSurfaceStrong.withValues(alpha: 0.92),
              colors.cardSurface.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(
            color: group.isClosed
                ? colors.borderStrong
                : group.groupType.color.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: type badge + privacy icon ──
            Row(
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: group.groupType.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(CoolRadii.pill),
                    border: Border.all(
                      color: group.groupType.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(group.groupType.icon, size: 12, color: group.groupType.color),
                      const SizedBox(width: 6),
                      Text(
                        group.groupType.label.toUpperCase(),
                        style: text.rayon(
                          const TextStyle(fontSize: 10),
                          fontWeight: FontWeight.w800,
                          color: group.groupType.color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Privacy icon
                Icon(group.privacy.icon, size: 14, color: colors.secondaryText),
                const SizedBox(width: 4),
                Text(
                  group.privacy.label.toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                ),
                if (group.isClosed) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                    ),
                    child: Text(
                      'CLOSED',
                      style: text.rayon(
                        const TextStyle(fontSize: 9),
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsRed,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ── Group name ──
            Text(
              group.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.rayonCondensed(
                const TextStyle(fontSize: 20, height: 1.1),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            if (group.description != null && group.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                group.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: colors.secondaryText,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Progress bar ──
            if (group.targetAmount > 0) ...[
              RsProgressBar(
                progress: group.progress,
                fillColor: group.groupType.color,
              ),
              const SizedBox(height: 8),
              // Amount row
              Row(
                children: [
                  Text(
                    '${fmt.format(group.currentTotal)} RWF',
                    style: text.mono(
                      const TextStyle(fontSize: 14),
                      fontWeight: FontWeight.w800,
                      color: RsColors.rsGoldLight,
                    ),
                  ),
                  Text(
                    ' / ${fmt.format(group.targetAmount)} RWF',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(group.progress * 100).toInt()}%',
                    style: text.mono(
                      const TextStyle(fontSize: 12),
                      fontWeight: FontWeight.w800,
                      color: group.groupType.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Footer: members + deadline ──
            Row(
              children: [
                Icon(Icons.people_alt_rounded, size: 14, color: colors.secondaryText),
                const SizedBox(width: 6),
                Text(
                  '${group.memberCount} MEMBERS',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                ),
                if (group.deadline != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.schedule_rounded, size: 14, color: colors.secondaryText),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('d MMM yyyy').format(group.deadline!).toUpperCase(),
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: group.isExpired ? RsColors.rsRed : colors.secondaryText,
                      letterSpacing: 0.5,
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
