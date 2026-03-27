import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import 'home_shared.dart';

// ═════════════════════════════════════════════════════════════════════
// FAN SAVINGS PLAN  (graph icon, +200 RWF today, ACTIVE)
// ═════════════════════════════════════════════════════════════════════

class HomeFanSavingsPlanCard extends StatelessWidget {
  const HomeFanSavingsPlanCard({
    super.key,
    this.balance,
    this.target,
    this.monthlyNetChange,
  });

  final int? balance;
  final int? target;
  final int? monthlyNetChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final liveTarget = target != null && target! > 0 ? target : null;
    final progress = balance != null && liveTarget != null
        ? (balance! / liveTarget).clamp(0.0, 1.0)
        : 0.0;
    final pctLabel = liveTarget == null ? '—' : '${(progress * 100).round()}%';
    final hasLiveBalance = balance != null;
    final statusColor = hasLiveBalance ? colors.success : colors.secondaryText;
    final trendColor = switch (monthlyNetChange) {
      null => colors.secondaryText,
      final value when value > 0 => colors.success,
      final value when value < 0 => colors.danger,
      _ => colors.secondaryText,
    };
    final trendLabel = switch (monthlyNetChange) {
      null => 'LIVE DATA PENDING',
      final value when value > 0 => '+${fmtAmt(value.abs())} RWF THIS MONTH',
      final value when value < 0 => '-${fmtAmt(value.abs())} RWF THIS MONTH',
      _ => '0 RWF THIS MONTH',
    };

    return HomeGlassCard(
      onTap: () => context.push(AppRoutes.groups),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + green graph icon + labels
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FAN SAVINGS PLAN',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasLiveBalance ? 'ACTIVE' : 'SYNCING',
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: CoolSpace.x3),
                        Text(
                          trendLabel,
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: trendColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Green rounded-rect icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.trending_up_rounded,
                  color: statusColor,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // Balance Row: 12,450 RWF ... 45%
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    balance == null ? '—' : fmtAmt(balance!),
                    style: context.coolText.rayonCondensed(
                      Theme.of(context).textTheme.displayMedium,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RWF',
                    style: context.coolText.rayonCondensed(
                      Theme.of(context).textTheme.headlineSmall,
                      fontWeight: FontWeight.w800,
                      color: RsColors.rsBlue,
                    ),
                  ),
                ],
              ),
              Text(
                pctLabel,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Green progress bar
          HomeProgressBar(value: progress.toDouble(), barColor: colors.success),
          const SizedBox(height: CoolSpace.x3),

          // Target label
          Text(
            liveTarget == null
                ? 'TARGET: PENDING • VIP TICKET FUND'
                : 'TARGET: RWF ${fmtAmt(liveTarget)} • VIP TICKET FUND',
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
