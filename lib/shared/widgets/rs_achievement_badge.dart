import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';

/// Metadata derived from [RsAchievement.badgeType].
class _BadgeMeta {
  const _BadgeMeta(this.emoji, this.name, this.description, this.isMilestone);

  final String emoji;
  final String name;
  final String description;
  final bool isMilestone; // milestone → gold border, activity → blue border

  static _BadgeMeta from(String type) => switch (type) {
    'ticket-buyer'      => const _BadgeMeta('🎫', 'Ticket Buyer', 'Purchased your first match ticket.', false),
    'monthly-active'    => const _BadgeMeta('📅', 'Monthly Active', 'Active for a full calendar month.', false),
    'top-recruiter'     => const _BadgeMeta('📣', 'Top Recruiter', 'Recruited 5+ new fans to the club.', true),
    'match-attendance'  => const _BadgeMeta('🏟️', 'Matchday Loyalist', 'Attended 10+ matches this season.', true),
    'first-purchase'    => const _BadgeMeta('🛍️', 'First Purchase', 'Made your first shop purchase.', false),
    'supporter'         => const _BadgeMeta('🤝', 'Club Supporter', 'Backed a community initiative.', false),
    'season-holder'     => const _BadgeMeta('🏅', 'Season Holder', 'Held a full-season membership.', true),
    _                   => const _BadgeMeta('⭐', 'Club Star', 'A loyal Gikundiro supporter.', false),
  };
}

/// Displays a 56 px circular achievement badge with label.
///
/// Earned badges show a coloured glow border (gold for milestones,
/// blue for activities). Locked badges are dimmed to 0.35 opacity.
/// Long-press opens a tooltip with the achievement description.
class RsAchievementBadge extends StatelessWidget {
  const RsAchievementBadge({required this.achievement, super.key});

  final RsAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final meta = _BadgeMeta.from(achievement.badgeType);

    final borderColor = meta.isMilestone
        ? RsColors.rsGold
        : RsColors.rsBlueLight;

    final bgColor = meta.isMilestone
        ? RsColors.rsGold.withValues(alpha: 0.12)
        : RsColors.rsBlueGlow;

    return Tooltip(
      message: meta.description,
      preferBelow: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: borderColor, width: 1.6),
            ),
            alignment: Alignment.center,
            child: Text(
              meta.emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 68,
            child: Text(
              meta.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
