import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import 'cool_card.dart';

class RsServiceCard extends StatelessWidget {
  const RsServiceCard({
    required this.icon,
    required this.name,
    required this.desc,
    required this.count,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String name;
  final String desc;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name. $desc. $count.',
      excludeSemantics: true,
      child: CoolCard(
      onTap: onTap,
      gradient: AppColors.rsBlueGradient,
      borderColor: AppColors.rsBlueBorder,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 12),
            Text(
              name,
              style: GoogleFonts.barlowCondensed(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.rsWhite,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.rsWhite.withValues(alpha: 0.82),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              count,
              style: GoogleFonts.dmMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.rsGoldLight,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
