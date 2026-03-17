import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../models/group.dart';
import '../../models/group_member.dart';
import 'group_detail_helpers.dart';

class GroupHeroCard extends StatelessWidget {
  const GroupHeroCard({required this.group, required this.members, super.key});

  final Group group;
  final List<GroupMember> members;

  @override
  Widget build(BuildContext context) {
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();

    return CoolCard(
      gradient: AppColors.cardGradient,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Text(
              group.name,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),

            // Badges
            Row(
              children: [
                if (group.type == 'saving')
                    StatusBadge.saving()
                else
                    StatusBadge.community(),
                const SizedBox(width: 8),
                if (group.visibility == 'public')
                    StatusBadge.public()
                else
                    StatusBadge.private(),
              ],
            ),
            const SizedBox(height: 24),

            // Total amount
            Text(
              groupFormatAmount(group.amount),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w900,
                fontFamily: GoogleFonts.dmMono().fontFamily,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Target: RWF ${groupFormatAmount(group.targetAmount)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.surface3,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 12),

            // Progress label
            Text(
              '$percent% reached',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 20),

            // Member count + frequency chips (merged from Group Facts)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                GroupHeroInfoChip(
                  icon: Icons.groups_2_outlined,
                  label: members.length == 1
                      ? '1 member'
                      : '${members.length} members',
                ),
                if (group.frequency != null && group.frequency!.isNotEmpty)
                  GroupHeroInfoChip(
                    icon: Icons.event_repeat_rounded,
                    label: groupFormatFrequency(group.frequency!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
