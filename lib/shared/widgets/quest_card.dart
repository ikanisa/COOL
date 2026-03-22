import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/status/services/quest_engine.dart';
import '../../../core/theme/cool_palette.dart';
import '../../core/l10n/l10n.dart';

/// Compact quest card with emoji, title, subtitle, and CTA.
///
/// Designed for horizontal carousel on the home screen.
class QuestCard extends StatelessWidget {
  const QuestCard({required this.quest, super.key});

  final CoolQuest quest;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: '${quest.title}. ${quest.subtitle}',
      hint: 'Opens this mission',
      child: GestureDetector(
        onTap: () => context.push(quest.route),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(quest.icon, size: 24, color: palette.text2),
              const SizedBox(height: 8),
              Text(
                quest.title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                quest.subtitle,
                style: GoogleFonts.dmSans(fontSize: 12, color: palette.text3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Semantics(
                label: context.l10n.openQuestAction,
                button: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Go →',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
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
    final palette = context.coolPalette;
    if (quests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 10),
          child: Text(
            'Suggested for you',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: palette.text3,
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