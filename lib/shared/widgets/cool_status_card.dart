import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/partners/rayon/models/rs_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/status/models/cool_status.dart';

/// Compact status card showing unified COOL tier, points, streak,
/// and progress to the next tier.
///
/// Designed to sit on the profile screen.
class CoolStatusCard extends StatelessWidget {
  const CoolStatusCard({required this.status, super.key});

  final CoolStatus status;

  @override
  Widget build(BuildContext context) {
    final tier = status.tier;

    return Container(
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
        border: Border.all(
          color: tier.color.withValues(alpha: 0.28),
        ),
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
                        color: AppColors.text3,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tier.label} Member',
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
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
                      backgroundColor: AppColors.surface3,
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
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ─── Streak row ────────────────────────────────────
          Row(
            children: [
              _StatPill(
                emoji: '🔥',
                label: '${status.currentStreak} streak',
              ),
              const SizedBox(width: 8),
              _StatPill(
                emoji: '🏆',
                label: '${status.longestStreak} best',
              ),
              if (status.streakGraceRemaining > 0) ...[
                const SizedBox(width: 8),
                _StatPill(
                  emoji: '🛡️',
                  label: '${status.streakGraceRemaining} grace',
                ),
              ],
            ],
          ),
        ],
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
          BoxShadow(
            color: tier.glowColor,
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _tierEmoji(tier),
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  static String _tierEmoji(FanTier tier) => switch (tier) {
    FanTier.blue => '🔵',
    FanTier.silver => '⚪',
    FanTier.gold => '🟡',
    FanTier.platinum => '💎',
  };
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}
