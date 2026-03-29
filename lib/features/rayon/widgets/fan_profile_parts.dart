part of '../screens/fan_profile_screen.dart';

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.membership,
    required this.user,
    required this.isRecoveringMembership,
    required this.onRecoverMembership,
  });

  final RsFanMembership? membership;
  final UserProfile? user;
  final bool isRecoveringMembership;
  final Future<void> Function() onRecoverMembership;

  @override
  Widget build(BuildContext context) {
    final fanName = membership?.displayName ?? user?.displayUserId ?? '';
    final tier = membership?.tier ?? FanTier.fan;
    final chapter = membership?.chapter ?? 'Official membership pending';
    final fanId = _displayId(user, membership);
    final initials = _initials(fanName);
    final progressMeta = membership == null
        ? null
        : _progressMeta(membership!.points, tier);

    return CoolCard(
      variant: CoolCardVariant.glass,
      borderColor: RsColors.rsRedBorder,
      blur: 14,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [RsColors.rsNavyLight, RsColors.rsRed],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: RsColors.rsWhite, width: 2.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: RsTextStyles.clubName(
                    color: RsColors.rsWhite,
                  ).copyWith(fontSize: 24),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fanName,
                      style: RsTextStyles.clubName(color: RsColors.rsWhite),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      fanId,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: RsColors.rsWhite.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          Row(
            children: [
              RsTierBadge(tier: tier),
              const SizedBox(width: 10),
              _ChapterChip(label: chapter),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          if (progressMeta != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: RsColors.rsRedBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'FAN POINTS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: RsColors.rsWhite,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${progressMeta.current} / ${progressMeta.threshold} Points',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: RsColors.rsGoldLight,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x4),
                  RsProgressBar(
                    progress: progressMeta.progress,
                    fillColor: RsColors.rsGold,
                    height: 12,
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  Center(
                    child: Text(
                      'Next Tier: ${progressMeta.targetTierLabel}'
                          .toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsWhite.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: RsColors.rsRedBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join to unlock exclusive perks.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RsColors.rsWhite.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  CoolButton(
                    label: 'Create / Restore Membership',
                    onTap: () {
                      onRecoverMembership();
                    },
                    isLoading: isRecoveringMembership,
                    icon: Icons.verified_user_outlined,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterChip extends StatelessWidget {
  const _ChapterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RsColors.rsWhite.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: context.coolText.rayon(
            const TextStyle(fontSize: 14),
            fontWeight: FontWeight.w600,
            color: RsColors.rsWhite.withValues(alpha: 0.82),
          ),
        ),
      ),
    );
  }
}

class _PerksAccessCard extends StatelessWidget {
  const _PerksAccessCard({required this.membership, required this.user});

  final RsFanMembership? membership;
  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final tier = membership?.tier ?? FanTier.fan;
    final currentTierIndex = FanTier.values.indexOf(tier);
    final benefits = _benefitsForDisplay(tier);
    final fanId = _displayId(user, membership);
    final hasMembership = membership != null;

    return CoolCard(
      gradient: colors.surfaceGradient,
      borderColor: RsColors.rsRedBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Perks & access',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
              ),
              if (hasMembership) RsTierBadge(tier: tier),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            hasMembership
                ? 'Pricing and match access unlocked.'
                : 'Create membership to unlock.',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 16),
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          ...benefits.map((benefit) {
            final active = currentTierIndex >= benefit.minTierIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PerkRow(benefit: benefit, active: active),
            );
          }),
          if (hasMembership) ...[
            const SizedBox(height: 14),
            CoolButton(
              label: context.l10n.showFanQr,
              variant: CoolButtonVariant.secondary,
              icon: Icons.qr_code_2_rounded,
              onTap: () => _showFanQr(context, fanId, tier),
            ),
          ],
        ],
      ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.benefit, required this.active});

  final _BenefitItem benefit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(benefit.icon, size: 22, color: colors.secondaryText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 15),
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsWhite,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  benefit.subtitle,
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 15),
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? colors.accent.withValues(alpha: 0.12)
                  : colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? colors.accent.withValues(alpha: 0.35)
                    : colors.border,
              ),
            ),
            child: Text(
              active ? 'Active' : 'Upgrade',
              style: context.coolText.rayon(
                const TextStyle(fontSize: 14),
                fontWeight: FontWeight.w700,
                color: active ? colors.accent : colors.tertiaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      gradient: colors.surfaceGradient,
      borderColor: RsColors.rsRedBorder,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: context.coolText.rayon(
              const TextStyle(fontSize: 16),
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentOrdersSection extends StatelessWidget {
  const _RecentOrdersSection({required this.ordersAsync});

  final AsyncValue<List<RsShopOrder>> ordersAsync;

  @override
  Widget build(BuildContext context) {
    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyStrip(message: 'No shop orders yet.');
        }

        final recentOrders = orders.take(3).toList(growable: false);
        return Column(
          children: recentOrders
              .map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OrderStatusCard(order: order),
                ),
              )
              .toList(growable: false),
        );
      },
      loading: () => const CoolSkeleton.card(),
      error: (error, stackTrace) =>
          const _EmptyStrip(message: 'Orders unavailable.'),
    );
  }
}

class _OrderStatusCard extends StatelessWidget {
  const _OrderStatusCard({required this.order});

  final RsShopOrder order;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final color = _orderStatusColor(context, order.status);

    return CoolCard(
      gradient: colors.surfaceGradient,
      borderColor: RsColors.rsRedBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order ${order.status.label.toUpperCase()}',
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 14),
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsWhite,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Text(
                  order.status.label,
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 14),
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            '${_formatRwf(order.total)} • ${DateFormat('dd MMM, HH:mm').format(order.createdAt)}',
            style: GoogleFonts.dmMono(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            order.deliveryAddress,
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            _orderStatusCopy(order.status),
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementSkeletonRow extends StatelessWidget {
  const _AchievementSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(width: 14),
      itemBuilder: (context, index) => const Column(
        children: [
          CoolSkeleton(width: 56, height: 56, borderRadius: 28),
          SizedBox(height: CoolSpace.x2),
          CoolSkeleton(width: 64, height: 14, borderRadius: 6),
        ],
      ),
    );
  }
}

class _ProgressMeta {
  const _ProgressMeta({
    required this.current,
    required this.threshold,
    required this.targetTierLabel,
    required this.progress,
  });

  final int current;
  final int threshold;
  final String targetTierLabel;
  final double progress;
}

class _BenefitItem {
  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.minTierIndex,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int minTierIndex;
}

_ProgressMeta _progressMeta(int points, FanTier tier) {
  switch (tier) {
    case FanTier.fan:
      return _ProgressMeta(
        current: points,
        threshold: 1000,
        targetTierLabel: 'Silver',
        progress: (points / 1000).clamp(0, 1).toDouble(),
      );
    case FanTier.bronze:
      return _ProgressMeta(
        current: points,
        threshold: 2000,
        targetTierLabel: 'Gold',
        progress: (points / 2000).clamp(0, 1).toDouble(),
      );
    case FanTier.gold:
      return _ProgressMeta(
        current: points,
        threshold: 5000,
        targetTierLabel: 'Platinum',
        progress: (points / 5000).clamp(0, 1).toDouble(),
      );
    case FanTier.platinum:
      return _ProgressMeta(
        current: points,
        threshold: 5000,
        targetTierLabel: 'Platinum',
        progress: 1,
      );
  }
}

String _displayId(UserProfile? user, RsFanMembership? membership) {
  if (membership != null && membership.membershipNumber.isNotEmpty) {
    return membership.membershipNumber;
  }
  return user?.displayUserId ?? 'Membership pending';
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'RS';
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
}

String _tierName(FanTier tier) => switch (tier) {
  FanTier.fan => 'Blue',
  FanTier.bronze => 'Silver',
  FanTier.gold => 'Gold',
  FanTier.platinum => 'Platinum',
};

List<_BenefitItem> _benefitsForDisplay(FanTier tier) {
  final gold = <_BenefitItem>[
    const _BenefitItem(
      icon: Icons.confirmation_number_rounded,
      title: 'Priority Tickets',
      subtitle: 'Early access to match tickets',
      minTierIndex: 2,
    ),
    const _BenefitItem(
      icon: Icons.shopping_bag_rounded,
      title: '10% Shop',
      subtitle: '10% off all merchandise',
      minTierIndex: 2,
    ),
    const _BenefitItem(
      icon: Icons.auto_awesome_rounded,
      title: 'VIP Events',
      subtitle: 'Exclusive fan meet-ups',
      minTierIndex: 2,
    ),
  ];

  if (tier == FanTier.platinum) {
    return <_BenefitItem>[
      ...gold,
      const _BenefitItem(
        icon: Icons.handshake_rounded,
        title: 'Meet & Greet',
        subtitle: 'Player meet & greet access',
        minTierIndex: 3,
      ),
      const _BenefitItem(
        icon: Icons.checkroom_rounded,
        title: 'Free Kit',
        subtitle: 'Free official kit per season',
        minTierIndex: 3,
      ),
    ];
  }

  return gold;
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}

Color _orderStatusColor(BuildContext context, OrderStatus status) {
  final colors = context.coolSemanticColors;
  return switch (status) {
    OrderStatus.pending => RsColors.rsGoldLight,
    OrderStatus.paid || OrderStatus.confirmed => colors.accent,
    OrderStatus.packed || OrderStatus.shipped => RsColors.rsNavyPale,
    OrderStatus.fulfilled || OrderStatus.delivered => RsColors.rsWhite,
    OrderStatus.cancelled => colors.tertiaryText,
  };
}

String _orderStatusCopy(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => 'Awaiting payment confirmation',
    OrderStatus.paid => 'Payment received',
    OrderStatus.confirmed => 'Confirmed, processing',
    OrderStatus.packed => 'Packed, ready to ship',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.fulfilled || OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
  };
}

void _showFanQr(BuildContext context, String fanId, FanTier tier) {
  final colors = context.coolSemanticColors;
  showCoolBottomSheet<void>(
    context: context,
    backgroundColor: colors.elevatedBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fan Access QR',
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
            ),
            const SizedBox(height: 6),
            Text(
              '$fanId • ${_tierName(tier).toUpperCase()}',
              style: GoogleFonts.dmMono(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            DecoratedBox(
              decoration: BoxDecoration(
                color: RsColors.rsWhite,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: fanId,
                  size: 200,
                  backgroundColor: Colors.transparent,
                  eyeStyle: const QrEyeStyle(
                    color: RsColors.rsRed,
                    eyeShape: QrEyeShape.square,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: RsColors.rsRed,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Text(
              'Show at stadium gates',
              style: context.coolText.rayon(
                const TextStyle(fontSize: 14),
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
