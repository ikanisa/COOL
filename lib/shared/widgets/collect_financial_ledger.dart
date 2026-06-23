part of 'collect_financial_components.dart';

class LedgerRow extends StatelessWidget {
  LedgerRow.confirmed({required Contribution contribution, super.key})
    : title = compactCollectIdLabel(contribution.supporterLabel),
      amountRwf = contribution.amountRwf,
      meta = formatCollectDateTime(contribution.createdAt),
      transactionId = contribution.transactionId,
      tone = CollectStatusTone.success,
      action = null;

  LedgerRow.review({
    required ParsedPaymentEvent event,
    required this.action,
    super.key,
  }) : title = 'Needs review',
       amountRwf = event.amountRwf,
       meta =
           'Confidence ${(event.confidence * 100).round()}% · ${event.senderLabel}',
       transactionId = event.transactionId,
       tone = CollectStatusTone.warning;

  final String title;
  final int amountRwf;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Column(
        children: [
          ActivityFeedItem(
            title: title,
            amount: amountRwf,
            meta: meta,
            transactionId: transactionId,
            tone: tone,
          ),
          if (action != null) ...[CollectSpacing.gap12, action!],
        ],
      ),
    );
  }
}

class ActivityFeedItem extends StatelessWidget {
  const ActivityFeedItem({
    required this.title,
    required this.amount,
    required this.meta,
    this.transactionId,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
          child: Row(
            children: [
              CollectToneIcon(icon: CollectIcons.profile, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        transactionId!,
                        style: CollectTypography.mono(colors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRwf(amount),
                  style: CollectTypography.amountCompact(amountColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
