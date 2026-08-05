part of 'collection_detail_screen.dart';

class _ContributionTimeline extends StatelessWidget {
  const _ContributionTimeline({required this.contributions});

  final List<Contribution> contributions;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < contributions.length; index++) ...[
            _TimelineRow(contribution: contributions[index]),
            if (index != contributions.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 64,
                color: colors.panelBorder,
              ),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.contribution});

  final Contribution contribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final supporter = compactCollectIdLabel(
      contribution.supporterLabel,
    ).replaceFirst('#', '');
    final createdAt = formatCollectDateTime(contribution.createdAt);
    final amount = formatRwf(contribution.amountRwf);
    final semanticLabel = 'Contribution $supporter, $amount, $createdAt';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x4,
          vertical: CollectSpacing.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.statusBackground(CollectStatusTone.info),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors
                            .statusForeground(CollectStatusTone.info)
                            .withValues(alpha: 0.24),
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        CollectIcons.profile,
                        size: 21,
                        color: colors.statusForeground(CollectStatusTone.info),
                      ),
                    ),
                  ),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          supporter,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        CollectSpacing.gap4,
                        Text(
                          createdAt,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            CollectSpacing.gapW8,
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount,
                      style: CollectTypography.amountLarge(colors.textPrimary),
                    ),
                  ),
                  if (contribution.transactionId != null) ...[
                    CollectSpacing.gap8,
                    Icon(
                      CollectIcons.check,
                      size: 18,
                      color: colors.textSecondary,
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
