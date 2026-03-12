import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import 'cool_card.dart';

/// Fan-club card with join/joined toggle and stats strip.
class RsFanClubCard extends StatelessWidget {
  const RsFanClubCard({
    required this.club,
    required this.isJoined,
    required this.onJoinTap,
    super.key,
  });

  final RsFanClub club;
  final bool isJoined;
  final VoidCallback onJoinTap;

  // ── Region → banner gradient ─────────────────────────────────────

  static LinearGradient _bannerGradient(String region) {
    final lower = region.toLowerCase();
    if (lower.contains('kigali')) {
      return const LinearGradient(
        colors: [Color(0xFF0A1A50), Color(0xFF0D2878)],
      );
    }
    if (lower.contains('south') || lower.contains('huye')) {
      return const LinearGradient(
        colors: [Color(0xFF0E1A4A), Color(0xFF152260)],
      );
    }
    if (lower.contains('north') || lower.contains('musanze')) {
      return const LinearGradient(
        colors: [Color(0xFF071240), Color(0xFF0B1D5A)],
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF091540), Color(0xFF0D1E6A)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${club.name}. ${club.region}. '
          '${isJoined ? 'Joined' : 'Not joined'}. '
          '${club.memberCount} members.',
      excludeSemantics: true,
      child: CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: isJoined
          ? RsColors.rsGold.withValues(alpha: 0.5)
          : RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Banner ──────────────────────────────────────────────
          Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: _bannerGradient(club.region),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // Icon circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: RsColors.rsBlueGlow,
                    border: Border.all(
                      color: RsColors.rsBlueBorder,
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.music_note_rounded, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 12),

                // Name + region
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        club.name,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.rsWhite,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        club.region,
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: RsColors.rsBluePale,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Join / Joined button
                _JoinButton(isJoined: isJoined, onTap: onJoinTap),
              ],
            ),
          ),

          // ── Description ────────────────────────────────────────
          if (club.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                club.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.35,
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── Stats strip ────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                _Stat(label: 'Members', value: '${club.memberCount}'),
                _divider(),
                const _Stat(label: 'Events', value: '—'),
                _divider(),
                const _Stat(label: 'Rating', value: '—'),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  static Widget _divider() => Container(
    width: 1,
    height: 24,
    color: AppColors.border,
  );
}

// ── Join / Joined button ─────────────────────────────────────────────

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.isJoined, required this.onTap});

  final bool isJoined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isJoined ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isJoined ? RsColors.rsBlueGlow : RsColors.rsBlue,
          borderRadius: BorderRadius.circular(30),
          border: isJoined
              ? Border.all(color: RsColors.rsBlueBorder)
              : null,
        ),
        child: Text(
          isJoined ? '✓ Joined' : 'Join',
          style: GoogleFonts.barlowCondensed(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isJoined ? AppColors.blue : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Stats strip column ───────────────────────────────────────────────

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: RsColors.rsGoldLight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}
