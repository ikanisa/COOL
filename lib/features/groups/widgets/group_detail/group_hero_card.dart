import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../models/group.dart';
import '../../models/group_member.dart';
import 'group_detail_helpers.dart';

/// Group hero card matching the design screenshot:
///
/// ┌────────────────────────────────────────────┐
/// │  PRIVATE GROUP              ┌──────────┐   │
/// │                             │ 4         │   │
/// │  FAMILY                     │ MEMBERS   │   │
/// │  SUMMER                     └──────────┘   │
/// │  TRIP                                      │
/// │                                            │
/// │  TOTAL BALANCE                             │
/// │  450,000                           RWF     │
/// │                                            │
/// │  PROGRESS                          38%     │
/// │  ████████████████████                      │
/// │  0 RWF          TARGET: 1,200,000 RWF      │
/// └────────────────────────────────────────────┘
class GroupHeroCard extends StatelessWidget {
  const GroupHeroCard({required this.group, required this.members, super.key});

  final Group group;
  final List<GroupMember> members;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isPrivate = group.visibility == 'private';
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      padding: const EdgeInsets.all(CoolSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Top row: visibility label + member count box ─────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  isPrivate ? 'PRIVATE GROUP' : 'PUBLIC GROUP',
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  border: Border.all(color: colors.borderStrong),
                ),
                child: Column(
                  children: [
                    Text(
                      '${members.length}',
                      style: text.mono(
                        theme.textTheme.titleMedium,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      'MEMBERS',
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Group name (giant condensed) ─────────────────────
          Text(
            group.name.toUpperCase(),
            style: text.rayonCondensed(
              theme.textTheme.displaySmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              height: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),

          // ─── Total balance section ────────────────────────────
          Text(
            'TOTAL BALANCE',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatCompact(group.amount.toDouble()),
                style: text.mono(
                  const TextStyle(fontSize: 40),
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RWF',
                style: text.mono(
                  theme.textTheme.titleSmall,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // ─── Progress section ─────────────────────────────────
          Row(
            children: [
              Text(
                'PROGRESS',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: text.mono(
                  theme.textTheme.labelMedium,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.overlaySurface,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Amount range labels
          Row(
            children: [
              Text(
                '${groupFormatAmount(0)} RWF',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
              const Spacer(),
              Text(
                'TARGET: ${groupFormatAmount(group.targetAmount)} RWF',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatCompact(double amount) {
    return NumberFormat.decimalPattern('en').format(amount.toInt());
  }
}
