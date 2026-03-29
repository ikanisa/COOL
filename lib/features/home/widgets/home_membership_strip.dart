import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../rayon/models/rs_models.dart';
import 'home_shared.dart';

// ═════════════════════════════════════════════════════════════════════
// 2. MEMBERSHIP STRIP  (crown icon, tier label, fan points)
// ═════════════════════════════════════════════════════════════════════

class HomeMembershipStrip extends StatelessWidget {
  const HomeMembershipStrip({
    super.key,
    required this.membership,
    required this.isRecovering,
    required this.onRecover,
  });

  final FanMembership? membership;
  final bool isRecovering;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final tier = membership?.tier.label ?? 'Guest';
    final points = membership?.points ?? 0;

    return HomeGlassCard(
      onTap: () => context.push(AppRoutes.rayonMembership),
      child: Row(
        children: [
          // Crown icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: RsColors.rsRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(CoolRadii.lg),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: RsColors.rsRed,
              size: 26,
            ),
          ),
          const SizedBox(width: CoolSpace.x4),

          // Tier label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT TIER',
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tier.toUpperCase(),
                  style: context.coolText.rayonCondensed(
                    Theme.of(context).textTheme.headlineSmall,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          // Fan points
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'FAN POINTS',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                fmtAmt(points),
                style: context.coolText.mono(
                  Theme.of(context).textTheme.headlineSmall,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
