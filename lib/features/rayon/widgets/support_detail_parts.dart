part of '../screens/support_detail_screen.dart';

class _SupportCommandCard extends StatelessWidget {
  const _SupportCommandCard({
    required this.initiative,
    required this.paymentRoute,
    required this.amount,
  });

  final RsInitiative initiative;
  final PartnerPaymentRoute? paymentRoute;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF06152D), Color(0xFF0B2351), Color(0xFF143B72)],
      ),
      borderColor: RsColors.rsRedBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verified giving',
            style: text.rayon(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.72),
              letterSpacing: 0.35,
            ),
          ),
          SizedBox(height: space.x3),
          Text(
            'Official Support Desk',
            style: text.rayonCondensed(
              theme.textTheme.headlineMedium,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Direct club-backed routing and visible contribution progress.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          SizedBox(height: space.x3 + 2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _DetailSignalPill(
                icon: Icons.favorite_border_rounded,
                label:
                    '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} supporters',
              ),
              _DetailSignalPill(
                icon: Icons.payments_outlined,
                label: paymentRoute == null
                    ? _formatRwf(amount)
                    : paymentRoute!.amountLabel(amount),
              ),
              _DetailSignalPill(
                icon: paymentRoute == null
                    ? Icons.timelapse_rounded
                    : Icons.shield_outlined,
                label: paymentRoute == null
                    ? 'Payment route syncing'
                    : '${paymentRoute!.providerLabel} live',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailSignalPill extends StatelessWidget {
  const _DetailSignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.labelMedium,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.initiative, required this.categoryColor});

  final RsInitiative initiative;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    categoryColor.withValues(alpha: 0.68),
                    RsColors.rsRed,
                    const Color(0xFF091331),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            Positioned(
              right: 18,
              top: 6,
              child: Icon(
                _categoryIcon(initiative.category.value),
                size: 82,
                color: RsColors.rsWhite.withValues(alpha: 0.92),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Text(
                'Rayon Sports Cause',
                style: text.rayon(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsWhite.withValues(alpha: 0.85),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      colors.overlaySurface.withValues(alpha: 0.22),
                      colors.overlaySurface,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CauseSummaryCard extends StatelessWidget {
  const _CauseSummaryCard({
    required this.initiative,
    required this.categoryColor,
  });

  final RsInitiative initiative;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final percentage = (initiative.progress * 100).round();

    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CategoryPill(
                  label: initiative.category.value.toUpperCase(),
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatRwf(initiative.raisedAmount),
                    style: text.mono(
                      theme.textTheme.titleMedium,
                      fontWeight: FontWeight.w800,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    'raised so far',
                    style: text.rayon(
                      theme.textTheme.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            initiative.title,
            style: text.rayonCondensed(
              theme.textTheme.headlineMedium,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            initiative.description,
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          RsProgressBar(
            progress: initiative.progress,
            fillColor: categoryColor,
            height: 8,
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} supporters',
                  style: text.rayon(
                    theme.textTheme.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$percentage% of ${_formatRwf(initiative.targetAmount)}',
                textAlign: TextAlign.right,
                style: text.mono(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: categoryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supporter perks',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Recognition scales with your contribution.',
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const _PerkRow(threshold: '1,000+', perk: 'Supporter badge'),
          const SizedBox(height: 10),
          const _PerkRow(threshold: '5,000+', perk: 'Name on plaque'),
          const SizedBox(height: 10),
          const _PerkRow(
            threshold: '20,000+',
            perk: 'VIP opening ceremony invite',
          ),
        ],
      ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.threshold, required this.perk});

  final String threshold;
  final String perk;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: RsColors.rsGold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            threshold,
            style: text.mono(
              theme.textTheme.labelMedium,
              fontWeight: FontWeight.w700,
              color: RsColors.rsGoldLight,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            perk,
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: context.coolSemanticColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _SupportCheckoutCard extends StatelessWidget {
  const _SupportCheckoutCard({
    required this.amount,
    required this.ctaLabel,
    required this.isLoading,
    required this.onAmountSelected,
    this.onTap,
    this.paymentRoute,
  });

  final int amount;
  final String ctaLabel;
  final bool isLoading;
  final ValueChanged<int> onAmountSelected;
  final VoidCallback? onTap;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Back this cause',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose an amount and confirm support.',
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          RsAmountSelector(
            amounts: const [1000, 2000, 5000, 10000, 20000],
            allowCustom: true,
            selectedAmount: amount,
            onAmountSelected: onAmountSelected,
          ),
          const SizedBox(height: 14),
          _SupportPaymentSummary(amount: amount, paymentRoute: paymentRoute),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: ctaLabel,
            icon: Icons.favorite_border_rounded,
            isDisabled: onTap == null,
            isLoading: isLoading,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _SupportPaymentSummary extends StatelessWidget {
  const _SupportPaymentSummary({required this.amount, this.paymentRoute});

  final int amount;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final title = paymentRoute == null
        ? 'Checkout unavailable'
        : paymentRoute!.providerLabel;
    final detail = paymentRoute == null
        ? 'A club admin must activate payment routing before checkout can open.'
        : 'Pay ${paymentRoute!.amountLabel(amount)} to ${paymentRoute!.payToLabel}. Status updates after ${paymentRoute!.reconciliationLabel}.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RsColors.rsRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RsColors.rsRedBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: RsColors.rsRedGlow,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.phone_in_talk_rounded,
              color: RsColors.rsWhite,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.rayon(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsWhite,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  detail,
                  style: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSupportersCard extends StatelessWidget {
  const _RecentSupportersCard({
    required this.contributionsAsync,
    required this.onRefreshStatus,
  });

  final AsyncValue<List<RsInitiativeContribution>> contributionsAsync;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent support',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Confirmed and pending support activity.',
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          contributionsAsync.when(
            data: (contributions) {
              if (contributions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      'Support activity appears after checkout updates.',
                      textAlign: TextAlign.center,
                      style: text.rayon(
                        theme.textTheme.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < contributions.length; i++) ...[
                    _SupporterRow(contribution: contributions[i]),
                    if (i < contributions.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: colors.borderStrong),
                      ),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  CoolSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 14,
                  ),
                  SizedBox(height: CoolSpace.x3),
                  CoolSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 14,
                  ),
                  SizedBox(height: CoolSpace.x3),
                  CoolSkeleton(
                    width: double.infinity,
                    height: 52,
                    borderRadius: 14,
                  ),
                ],
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Text(
                    'Recent support activity failed to load.',
                    textAlign: TextAlign.center,
                    style: text.rayon(
                      theme.textTheme.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: colors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  TextButton.icon(
                    onPressed: onRefreshStatus,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(context.l10n.tryAgain),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupporterRow extends StatelessWidget {
  const _SupporterRow({required this.contribution});

  final RsInitiativeContribution contribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final supporterName = contribution.supporterName ?? 'Supporter';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [RsColors.rsNavyLight, RsColors.rsRed],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: RsColors.rsRedBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(supporterName),
            style: text.rayonCondensed(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supporterName,
                style: text.rayon(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                '${_contributionStatusLabel(contribution.status)} • ${DateFormat('dd MMM, HH:mm').format(contribution.createdAt)}',
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: _contributionStatusColor(context, contribution.status),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _formatRwf(contribution.amount),
          style: text.mono(
            theme.textTheme.labelLarge,
            fontWeight: FontWeight.w700,
            color: colors.accent,
          ),
        ),
      ],
    );
  }
}

class _PendingContributionCard extends StatelessWidget {
  const _PendingContributionCard({
    required this.contribution,
    required this.onRefreshStatus,
  });

  final RsInitiativeContribution contribution;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: RsColors.rsGold.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Payment Status',
                style: text.rayonCondensed(
                  theme.textTheme.headlineSmall,
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                ),
              ),
              const Spacer(),
              _ContributionStatusChip(status: contribution.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Pending until MoMo confirms.',
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          _PendingContributionMeta(
            label: 'Amount',
            value: _formatRwf(contribution.amount),
          ),
          _PendingContributionMeta(
            label: 'MoMo ref',
            value: contribution.momoReference,
          ),
          _PendingContributionMeta(
            label: 'Started',
            value: DateFormat('dd MMM, HH:mm').format(contribution.createdAt),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRefreshStatus,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: Text(context.l10n.refreshPaymentStatus),
          ),
        ],
      ),
    );
  }
}

class _PendingContributionMeta extends StatelessWidget {
  const _PendingContributionMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: text.rayon(
                theme.textTheme.bodySmall,
                fontWeight: FontWeight.w600,
                color: colors.tertiaryText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.mono(
                theme.textTheme.bodySmall,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionStatusChip extends StatelessWidget {
  const _ContributionStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    final color = _contributionStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        _contributionStatusLabel(status).toUpperCase(),
        style: text.rayon(
          theme.textTheme.labelMedium,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: text.rayon(
          theme.textTheme.labelMedium,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DetailStateCard extends StatelessWidget {
  const _DetailStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CoolCard(
          borderColor: colors.borderStrong,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: colors.secondaryText),
              const SizedBox(height: CoolSpace.x3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.rayonCondensed(
                  theme.textTheme.headlineSmall,
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: text.rayon(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              CoolButton(
                label: actionLabel,
                onTap: onTap,
                fullWidth: false,
                variant: CoolButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLoadingState extends StatelessWidget {
  const _DetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 96),
      child: Column(
        children: [
          CoolSkeleton(width: double.infinity, height: 140, borderRadius: 22),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
        ],
      ),
    );
  }
}

RsInitiativeContribution? _findContributionById(
  List<RsInitiativeContribution>? contributions,
  String? contributionId,
) {
  if (contributions == null ||
      contributionId == null ||
      contributionId.isEmpty) {
    return null;
  }

  for (final contribution in contributions) {
    if (contribution.id == contributionId) {
      return contribution;
    }
  }

  return null;
}

String _contributionStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'confirmed':
      return 'Confirmed';
    case 'failed':
      return 'Failed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Pending';
  }
}

Color _contributionStatusColor(BuildContext context, String status) {
  final colors = context.coolSemanticColors;
  switch (status.toLowerCase()) {
    case 'confirmed':
      return colors.accent;
    case 'failed':
      return const Color(0xFFFF7A7A);
    case 'cancelled':
      return colors.tertiaryText;
    default:
      return RsColors.rsGoldLight;
  }
}

String _formatRwf(int amount) {
  return 'RWF ${NumberFormat.decimalPattern('en').format(amount)}';
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'youth':
      return Icons.child_care_rounded;
    case 'matchday':
      return Icons.stadium_rounded;
    case 'infrastructure':
      return Icons.construction_rounded;
    case 'charity':
      return Icons.favorite_rounded;
    default:
      return Icons.handshake_rounded;
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  if (parts.isEmpty) {
    return 'RS';
  }
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
