import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import 'cool_card.dart';

class RsClubCard extends StatelessWidget {
  const RsClubCard({
    required this.club,
    required this.joined,
    required this.onTap,
    super.key,
  });

  final RsFanClub club;
  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      onTap: onTap,
      gradient: AppColors.cardGradient,
      borderColor: joined
          ? AppColors.rsGold.withValues(alpha: 0.55)
          : AppColors.rsBlueBorder,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    club.name,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.rsWhite,
                    ),
                  ),
                ),
                if (joined)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rsGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      'JOINED',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.rsGoldLight,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              club.region,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.rsBluePale,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              club.description,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${club.memberCount} members',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.rsGoldLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
