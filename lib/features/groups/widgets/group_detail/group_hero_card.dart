import 'package:flutter/material.dart';

import '../../../../core/theme/cool_foundations.dart';
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final isSaving = group.type == 'saving';
    final accent = isSaving ? colors.accent : colors.warning;
    final surface = isSaving ? colors.financialSurface : colors.teamSurface;
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();

    return CoolCard(
      backgroundColor: surface,
      borderColor: colors.border,
      padding: const EdgeInsets.all(CoolSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              if (isSaving)
                const StatusBadge.saving()
              else
                const StatusBadge.community(),
              const SizedBox(width: CoolSpace.x2),
              if (group.visibility == 'public')
                const StatusBadge.public()
              else
                const StatusBadge.private(),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          Text(
            '${groupFormatAmount(group.amount)} RWF',
            style: text.mono(
              theme.textTheme.displaySmall,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Target: RWF ${groupFormatAmount(group.targetAmount)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.cardSurfaceStrong,
              color: accent,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            '$percent% reached',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Wrap(
            spacing: CoolSpace.x3,
            runSpacing: CoolSpace.x2,
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
    );
  }
}
