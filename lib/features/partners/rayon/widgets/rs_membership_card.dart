import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../models/rs_models.dart';

class RsMembershipCard extends StatelessWidget {
  const RsMembershipCard({
    required this.fanName,
    required this.fanId,
    required this.tier,
    required this.chapter,
    required this.year,
    required this.perks,
    super.key,
  });

  final String fanName;
  final String fanId;
  final FanTier tier;
  final String chapter;
  final int year;
  final List<String> perks;

  String get _tierLabel => switch (tier) {
    FanTier.blue => 'BLUE',
    FanTier.silver => 'SILVER',
    FanTier.gold => 'GOLD',
    FanTier.platinum => 'PLATINUM',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RsColors.rsMembershipGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RsColors.rsBlueBorder),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DiagonalStripePainter()),
              ),
            ),
            Positioned(
              right: -12,
              top: 18,
              child: IgnorePointer(
                child: Text(
                  '⚽',
                  style: TextStyle(
                    fontSize: 108,
                    color: RsColors.rsWhite.withValues(alpha: 0.07),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tierLabel,
                        style: RsTextStyles.badge(color: RsColors.rsGoldLight),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.favorite_rounded,
                        size: 20,
                        color: palette.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    fanName,
                    style: RsTextStyles.clubName(
                      color: RsColors.rsWhite,
                    ).copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fanId,
                    style: GoogleFonts.dmMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: RsColors.rsWhite.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Since $year • $chapter',
                    style: GoogleFonts.barlow(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: RsColors.rsWhite.withValues(alpha: 0.5),
                    ),
                  ),
                  if (perks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: perks
                          .map((perk) => _PerkChip(label: perk))
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerkChip extends StatelessWidget {
  const _PerkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RsColors.rsWhite.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: RsColors.rsWhite.withValues(alpha: 0.85),
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _DiagonalStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = RsColors.rsWhite.withValues(alpha: 0.02)
      ..strokeWidth = 1.2;

    const spacing = 18.0;
    final max = size.width + size.height;
    for (double offset = -size.height; offset < max; offset += spacing) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
