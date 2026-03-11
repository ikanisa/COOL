import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';

class RsTierBadge extends StatelessWidget {
  const RsTierBadge({required this.tier, super.key});

  final FanTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: tier.glowColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tier.color.withValues(alpha: 0.7)),
      ),
      child: Text(
        tier.label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: tier == FanTier.silver ? AppColors.text : tier.color,
        ),
      ),
    );
  }
}
