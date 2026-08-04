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
    this.prioritizeContext = false,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final VoidCallback? onTap;
  final bool prioritizeContext;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    final stackAmount =
        prioritizeContext ||
        MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final amountText = Text(
      formatRwf(amount),
      style: CollectTypography.amountCompact(amountColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
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
                    Text(
                      compactCollectIdLabel(title),
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: CollectTypography.weightBold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      Semantics(
                        label: 'Transaction reference $transactionId',
                        child: ExcludeSemantics(
                          child: Text(
                            _compactTransactionReference(transactionId!),
                            style: CollectTypography.mono(colors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    if (stackAmount) ...[CollectSpacing.gap8, amountText],
                  ],
                ),
              ),
              if (!stackAmount) ...[
                CollectSpacing.gapW12,
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: amountText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _compactTransactionReference(String value) {
  final reference = value.trim();
  if (reference.length <= 12) return 'Ref $reference';
  return 'Ref …${reference.substring(reference.length - 8)}';
}
