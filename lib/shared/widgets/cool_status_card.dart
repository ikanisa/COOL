import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/status/models/cool_status.dart';
import '../../core/theme/cool_palette.dart';
import '../../features/partners/rayon/models/rs_models.dart';

/// Compact status card showing unified COOL tier, points, streak,
/// and progress to the next tier.
///
/// Designed to sit on the profile screen.
class CoolStatusCard extends StatelessWidget {
  const CoolStatusCard({required this.status, super.key});

  final CoolStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final tier = status.tier;

    return Semantics(
      label:
          '${tier.label} member. ${status.totalPoints} points. '
          '${status.currentStreak} day streak.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tier.color.withValues(alpha: 0.18),
              tier.color.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tier.color.withValues(alpha: 0.28)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header: tier badge + label ─────────────────────
            Row(
              children: [
                _TierDot(tier: tier),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COOL Status',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.text3,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${tier.label} Member',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                    ],
                  ),
                ),
                // Points pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '${status.totalPoints} pts',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tier.color,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─── Progress bar ──────────────────────────────────
            if (tier != FanTier.platinum) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: status.progressToNextTier,
                        minHeight: 6,
                        backgroundColor: palette.surface3,
                        valueColor: AlwaysStoppedAnimation<Color>(tier.color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${status.pointsToNextTier} to ${_nextTierLabel(tier)}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: palette.text3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // ─── Streak row ────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatPill(
                  icon: Icons.local_fire_department_rounded,
                  label: '${status.currentStreak} streak',
                ),
                _StatPill(
                  icon: Icons.emoji_events_rounded,
                  label: '${status.longestStreak} best',
                ),
                if (status.streakGraceRemaining > 0)
                  _StatPill(
                    icon: Icons.shield_rounded,
                    label: '${status.streakGraceRemaining} grace',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _nextTierLabel(FanTier tier) => switch (tier) {
    FanTier.blue => 'Silver',
    FanTier.silver => 'Gold',
    FanTier.gold => 'Platinum',
    FanTier.platinum => 'Max',
  };
}

// ─── Internal widgets ─────────────────────────────────────────────

class _TierDot extends StatelessWidget {
  const _TierDot({required this.tier});
  final FanTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [tier.color, tier.color.withValues(alpha: 0.3)],
        ),
        boxShadow: [
          BoxShadow(color: tier.glowColor, blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Center(
        child: Icon(_tierIcon(tier), size: 18, color: Colors.white),
      ),
    );
  }

  static IconData _tierIcon(FanTier tier) => switch (tier) {
    FanTier.blue => Icons.favorite_rounded,
    FanTier.silver => Icons.workspace_premium_rounded,
    FanTier.gold => Icons.emoji_events_rounded,
    FanTier.platinum => Icons.diamond_rounded,
  };
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface3,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.text2),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
        ],
      ),
    );
  }
}
