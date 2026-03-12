import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import 'cool_card.dart';
import 'rs_tier_badge.dart';

class RsMembershipCard extends StatelessWidget {
  const RsMembershipCard({
    required this.membership,
    this.showPoints = true,
    super.key,
  });

  final RsFanMembership membership;
  final bool showPoints;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rayon Sports membership. ${membership.displayName}. '
          '${membership.tier.label} tier. '
          '${showPoints ? '${membership.points} points.' : ''}',
      excludeSemantics: true,
      child: CoolCard(
      gradient: AppColors.rsHeroGradient,
      borderColor: AppColors.rsBlueBorder,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAYON SPORTS FC',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.rsWhite,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        membership.displayName,
                        style: GoogleFonts.barlow(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.rsWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        membership.chapter,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.rsWhite.withValues(alpha: 0.74),
                        ),
                      ),
                    ],
                  ),
                ),
                RsTierBadge(tier: membership.tier),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _RsMetric(
                  label: 'Member ID',
                  value: membership.membershipNumber,
                ),
                const SizedBox(width: 12),
                if (showPoints)
                  _RsMetric(
                    label: 'Points',
                    value: '${membership.points}',
                    accentColor: AppColors.rsGoldLight,
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _RsMetric extends StatelessWidget {
  const _RsMetric({
    required this.label,
    required this.value,
    this.accentColor = AppColors.rsWhite,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.rsWhite.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
