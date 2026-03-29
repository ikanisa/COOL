import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import 'home_shared.dart';

// ═════════════════════════════════════════════════════════════════════
// OFFICIAL NETWORK STRIP  (label + ● CONNECTED)
// ═════════════════════════════════════════════════════════════════════

class HomeOfficialNetworkStrip extends StatelessWidget {
  const HomeOfficialNetworkStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'OFFICIAL NETWORK',
          style: context.coolText.mono(
            Theme.of(context).textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
            letterSpacing: 1.0,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'CONNECTED',
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.success,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// GLOBAL FAN NETWORK  (big fan count + fan clubs row)
// ═════════════════════════════════════════════════════════════════════

class HomeGlobalFanNetworkCard extends StatelessWidget {
  const HomeGlobalFanNetworkCard({
    super.key,
    required this.fanCount,
    required this.clubCount,
    required this.onTap,
  });

  final int? fanCount;
  final int? clubCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return HomeGlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  'GLOBAL FAN NETWORK',
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              HomeRedTag(
                label: fanCount == null && clubCount == null
                    ? 'SYNCING'
                    : 'LIVE DATA',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // Big number
          Text(
            fanCount == null ? '—' : fmtAmt(fanCount!),
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.displayLarge,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'FANS',
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.headlineMedium,
              fontWeight: FontWeight.w800,
              color: RsColors.rsRed,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: CoolSpace.x4),

          // Fan clubs row
          Row(
            children: [
              Text(
                'FAN CLUBS',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              Text(
                clubCount == null ? '—' : fmtAmt(clubCount!),
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsRed,
                ),
              ),
              const Spacer(),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.secondaryText,
                  size: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// FAN REWARDS  (● ACTIVE, points, progress bar)
// ═════════════════════════════════════════════════════════════════════

class HomeFanMissionsCard extends StatelessWidget {
  const HomeFanMissionsCard({
    super.key,
    required this.tokens,
    required this.progress,
  });

  final int? tokens;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final displayProgress = progress?.clamp(0, 1).toDouble() ?? 0.0;
    final pctLabel = progress == null
        ? '—'
        : '${(displayProgress * 100).round()}%';
    final isLive = tokens != null || progress != null;

    return HomeGlassCard(
      onTap: () => context.push(AppRoutes.rewards),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: FAN REWARDS + ● ACTIVE
          Row(
            children: [
              Text(
                'FAN REWARDS',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isLive ? 'ACTIVE' : 'SYNCING',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // Big token number
          Text(
            tokens == null ? '—' : fmtAmt(tokens!),
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.displayLarge,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),

          // POINTS label
          Text(
            'POINTS',
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.headlineMedium,
              fontWeight: FontWeight.w800,
              color: RsColors.rsRed,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),

          // PROGRESS TO REWARD + percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PROGRESS TO REWARD',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                pctLabel,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),

          // Blue progress bar
          HomeProgressBar(
            value: displayProgress.clamp(0, 1).toDouble(),
            barColor: RsColors.rsRed,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// CLUB & COMMUNITY  (RWF 37.5M raised, 50M target, 75%)
// ═════════════════════════════════════════════════════════════════════

class HomeClubCommunityCard extends StatelessWidget {
  const HomeClubCommunityCard({
    super.key,
    this.raisedAmount,
    this.targetAmount,
    this.supporterCount,
  });

  final int? raisedAmount;
  final int? targetAmount;
  final int? supporterCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final progress =
        raisedAmount != null && targetAmount != null && targetAmount! > 0
        ? (raisedAmount! / targetAmount!).clamp(0.0, 1.0)
        : 0.0;
    final progressLabel = targetAmount == null
        ? '—%'
        : '${(progress * 100).round()}%';

    return HomeGlassCard(
      onTap: () => context.push(AppRoutes.rayonSupport),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: CLUB & COMMUNITY ... RWF
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CLUB & COMMUNITY',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                'RWF',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.titleMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Big amount + 1.2k
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'RWF\n${_formatCompactMoney(raisedAmount)}',
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.displayMedium,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 0.95,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                _formatCompactCount(supporterCount),
                style: context.coolText.mono(
                  Theme.of(context).textTheme.headlineMedium,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // RAISED OF 50M TARGET ... 75%
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RAISED OF ${_formatCompactMoney(targetAmount)} TARGET',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                progressLabel,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),

          // Blue progress bar
          HomeProgressBar(value: progress, barColor: RsColors.rsRed),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// PARTNER NETWORK  (blue building icon, avatar row +12, ACTIVE DEALS)
// ═════════════════════════════════════════════════════════════════════

class HomePartnerNetworkCard extends StatelessWidget {
  const HomePartnerNetworkCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return HomeGlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + icon
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PARTNER NETWORK',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    Text(
                      'EXCLUSIVE\nBENEFITS.',
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.displaySmall,
                        fontWeight: FontWeight.w900,
                        color: RsColors.rsRed,
                        height: 0.95,
                      ),
                    ),
                  ],
                ),
              ),
              // Blue rounded-rect building icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: RsColors.rsRed,
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.business_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),

          // Avatar row + active deals
          Row(
            children: [
              // Stacked avatar circles
              SizedBox(
                width: 140,
                height: 40,
                child: Stack(
                  children: List.generate(4, (i) {
                    final avatarColors = [
                      colors.overlaySurface,
                      colors.overlaySurface,
                      colors.overlaySurface,
                      colors.overlaySurface,
                    ];
                    return Positioned(
                      left: i * 26.0,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: avatarColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.appBackground,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.storefront_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 16,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // +12 circle
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: RsColors.rsRed,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '—',
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: CoolSpace.x4),
              // ACTIVE DEALS
              Text(
                'ACTIVE\nDEALS',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 0.8,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// STADIUM LIGHTING  (inline card, gold progress bar + amounts)
// ═════════════════════════════════════════════════════════════════════

class HomeStadiumLightingCard extends StatelessWidget {
  const HomeStadiumLightingCard({
    super.key,
    this.raisedAmount,
    this.targetAmount,
  });

  final int? raisedAmount;
  final int? targetAmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final progress =
        raisedAmount != null && targetAmount != null && targetAmount! > 0
        ? (raisedAmount! / targetAmount!).clamp(0.0, 1.0)
        : 0.0;
    final progressLabel = targetAmount == null
        ? '—%'
        : '${(progress * 100).round()}%';

    return HomeGlassCard(
      onTap: () => context.push(AppRoutes.rayonSupport),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + percentage
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STADIUM\nLIGHTING',
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.headlineLarge,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      'COMMUNITY CONTRIBUTION\nPROJECT',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 1.0,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                progressLabel,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.headlineLarge,
                  fontWeight: FontWeight.w800,
                  color: RsColors.rsGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),

          // Gold/yellow progress bar
          HomeProgressBar(
            value: progress,
            barColor: RsColors.rsGold,
            barHeight: 8,
          ),
          const SizedBox(height: CoolSpace.x3),

          // RWF 37M RAISED + RWF 50M TARGET
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RWF ${_formatCompactMoney(raisedAmount)} RAISED',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'RWF ${_formatCompactMoney(targetAmount)} TARGET',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatCompactMoney(int? amount) {
  if (amount == null) {
    return '—';
  }
  if (amount < 1000) {
    return '$amount';
  }
  if (amount < 1000000) {
    final compact = amount / 1000;
    final keepDecimal = compact < 10 && compact.truncateToDouble() != compact;
    return '${compact.toStringAsFixed(keepDecimal ? 1 : 0)}K';
  }

  final compact = amount / 1000000;
  final keepDecimal = compact < 10 && compact.truncateToDouble() != compact;
  return '${compact.toStringAsFixed(keepDecimal ? 1 : 0)}M';
}

String _formatCompactCount(int? value) {
  if (value == null) {
    return '—';
  }
  if (value < 1000) {
    return fmtAmt(value);
  }

  final compact = value / 1000;
  final keepDecimal = compact < 10 && compact.truncateToDouble() != compact;
  return '${compact.toStringAsFixed(keepDecimal ? 1 : 0)}K';
}
