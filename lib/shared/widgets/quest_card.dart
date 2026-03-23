import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/status/services/quest_engine.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_card.dart';

/// Compact quest card with icon, title, subtitle, and CTA.
///
/// Designed for the horizontal home carousel.
class QuestCard extends StatelessWidget {
  const QuestCard({required this.quest, super.key});

  final CoolQuest quest;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '${quest.title}. ${quest.subtitle}',
      hint: 'Opens this mission',
      child: SizedBox(
        width: 220,
        child: CoolCard(
          onTap: () => context.push(quest.route),
          padding: const EdgeInsets.all(CoolSpace.x4),
          backgroundColor: colors.contactSurface,
          borderRadius: CoolRadii.sm,
          borderColor: colors.border,
          semanticsLabel: quest.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(quest.icon, size: 24, color: colors.secondaryText),
              const SizedBox(height: CoolSpace.x2),
              Text(
                quest.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                quest.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Semantics(
                label: context.l10n.openQuestAction,
                button: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x3,
                    vertical: CoolSpace.x1 + 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                  ),
                  child: Text(
                    'Go →',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrollable carousel of quest cards.
class QuestCarousel extends StatelessWidget {
  const QuestCarousel({required this.quests, super.key});

  final List<CoolQuest> quests;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (quests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 10),
          child: Text(
            'Suggested for you',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: colors.tertiaryText,
            ),
          ),
        ),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: quests.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return QuestCard(quest: quests[index]);
            },
          ),
        ),
      ],
    );
  }
}
