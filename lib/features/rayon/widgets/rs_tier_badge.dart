import 'package:flutter/material.dart';

import '../../../../core/theme/rs_text_styles.dart';
import '../models/rs_models.dart';
import '../theme/rs_theme.dart';

class RsTierBadge extends StatelessWidget {
  const RsTierBadge({required this.tier, super.key});

  RsTierBadge.fromPoints(int points, {super.key})
    : tier = FanTierX.fromPoints(points);

  final FanTier tier;

  bool get _showStar => tier == FanTier.gold || tier == FanTier.platinum;

  String get _label => switch (tier) {
    FanTier.fan => 'BLUE',
    FanTier.bronze => 'SILVER',
    FanTier.gold => 'GOLD',
    FanTier.platinum => 'PLATINUM',
  };

  @override
  Widget build(BuildContext context) {
    final color = RsTheme.tierColor(tier);
    final background = RsTheme.tierBackground(tier);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showStar) ...[
              Icon(Icons.star_rounded, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(_label, style: RsTextStyles.badge(color: color)),
          ],
        ),
      ),
    );
  }
}
