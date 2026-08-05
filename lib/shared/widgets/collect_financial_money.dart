part of 'collect_financial_components.dart';

class MoneyCard extends StatelessWidget {
  const MoneyCard({
    required this.label,
    required this.amount,
    this.detail,
    this.icon = CollectIcons.money,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String label;
  final int amount;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CollectToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          CollectSpacing.gap12,
          Text(
            formatRwf(amount),
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          if (detail != null) ...[
            CollectSpacing.gap4,
            Text(
              detail!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class AmountHero extends StatelessWidget {
  const AmountHero({
    required this.amount,
    required this.label,
    this.detail,
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.trim().isNotEmpty) ...[
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          CollectSpacing.gap8,
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRwf(amount),
            maxLines: 1,
            style: CollectTypography.amountHero(colors.textPrimary),
          ),
        ),
        if (detail != null) ...[
          CollectSpacing.gap8,
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class FinancialListRow extends StatelessWidget {
  const FinancialListRow({
    required this.title,
    required this.meta,
    this.amountRwf,
    this.subtitle,
    this.transactionId,
    this.leading,
    this.tone = CollectStatusTone.success,
    this.onTap,
    super.key,
  });

  final String title;
  final int? amountRwf;
  final String meta;
  final String? subtitle;
  final String? transactionId;
  final IconData? leading;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final stackAmount =
        amountRwf != null &&
        (MediaQuery.sizeOf(context).width < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3);
    final amount = amountRwf == null
        ? null
        : Text(
            formatRwf(amountRwf!),
            style: CollectTypography.amountCompact(colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.controlBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x4),
          child: Row(
            children: [
              CollectToneIcon(icon: leading ?? CollectIcons.money, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    if (subtitle != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: CollectTypography.transactionMeta(
                        colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      SelectableText(
                        transactionId!,
                        style: CollectTypography.transactionMeta(
                          colors.textMuted,
                        ),
                      ),
                    ],
                    if (stackAmount) ...[CollectSpacing.gap8, amount!],
                  ],
                ),
              ),
              if (amount != null && !stackAmount) ...[
                CollectSpacing.gapW12,
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: amount),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CollectIdCard extends StatelessWidget {
  const CollectIdCard({required this.publicId, super.key});

  final String publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Row(
        children: [
          _GroupIconBadge(
            icon: CollectIcons.profile,
            accent: colors.actionColor,
            size: 52,
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: CollectTypography.amountHero(colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MoneyHeroCard extends StatelessWidget {
  const MoneyHeroCard({
    required this.amount,
    required this.label,
    this.detail,
    this.primaryAction,
    this.secondaryAction,
    this.chips = const [],
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.medium),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: CollectRadius.cardLargeBorder,
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: CollectRadius.cardLargeBorder,
                border: Border.all(color: colors.borderSoft),
              ),
            ),
          ),
          Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.trim().isNotEmpty) ...[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  CollectSpacing.gap8,
                ],
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRwf(amount),
                    style: CollectTypography.amountHero(colors.textPrimary),
                  ),
                ),
                if (detail != null) ...[
                  CollectSpacing.gap8,
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: chips,
                  ),
                ],
                if (primaryAction != null || secondaryAction != null) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: [
                      // ignore: use_null_aware_elements
                      if (primaryAction != null) primaryAction!,
                      // ignore: use_null_aware_elements
                      if (secondaryAction != null) secondaryAction!,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String compactCollectIdLabel(String label) {
  return label
      .replaceFirst(RegExp(r'^Collect ID\s+'), '')
      .replaceFirst(RegExp(r'^#'), '');
}

class _IdentityTitle extends StatelessWidget {
  const _IdentityTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cleaned = compactCollectIdLabel(title);
    final isIdentity =
        cleaned != title.replaceFirst(RegExp(r'^#'), '') ||
        RegExp(r'^\d{4,}$').hasMatch(cleaned);
    if (!isIdentity) {
      return Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      cleaned,
      style: Theme.of(context).textTheme.titleSmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _GroupIconBadge extends StatelessWidget {
  const _GroupIconBadge({
    required this.icon,
    required this.accent,
    required this.size,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: accent, size: size * 0.52),
      ),
    );
  }
}
