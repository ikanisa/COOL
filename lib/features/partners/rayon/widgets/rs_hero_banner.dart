import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../models/rs_models.dart';
import 'rs_tier_badge.dart';

class RsHeroBanner extends StatelessWidget {
  const RsHeroBanner({
    required this.clubName,
    required this.nickname,
    required this.location,
    required this.fanId,
    required this.tier,
    required this.stats,
    super.key,
  });

  final String clubName;
  final String nickname;
  final String location;
  final String fanId;
  final FanTier tier;
  final List<RsHeroStat> stats;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RsColors.rsHeroGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RsColors.rsBlueBorder),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.rsBluePale.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RepeatingLinePainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.rsWhite.withValues(alpha: 0.1),
                          border: Border.all(
                            color: AppColors.rsWhite.withValues(alpha: 0.14),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.favorite_rounded, size: 26, color: AppColors.accent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nickname.toUpperCase(),
                              style: RsTextStyles.badge(
                                color: AppColors.rsGoldLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              clubName,
                              style: RsTextStyles.display(
                                color: AppColors.rsWhite,
                              ).copyWith(fontSize: 34),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              location,
                              style: GoogleFonts.barlow(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.rsWhite.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fanId,
                                    style: GoogleFonts.dmMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.rsWhite.withValues(
                                        alpha: 0.68,
                                      ),
                                    ),
                                  ),
                                ),
                                RsTierBadge(tier: tier),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < stats.length;
                            index++
                          ) ...[
                            Expanded(child: _StatItem(stat: stats[index])),
                            if (index != stats.length - 1)
                              Container(
                                width: 1,
                                height: 34,
                                color: AppColors.rsWhite.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                          ],
                        ],
                      ),
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

class RsHeroStat {
  const RsHeroStat({required this.value, required this.label});

  final String value;
  final String label;
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.stat});

  final RsHeroStat stat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.value,
            style: RsTextStyles.statValue(color: AppColors.rsWhite),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepeatingLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.rsWhite.withValues(alpha: 0.035)
      ..strokeWidth = 1;

    const spacing = 16.0;
    for (double y = -size.height; y < size.height * 2; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + (size.width * 0.22)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
