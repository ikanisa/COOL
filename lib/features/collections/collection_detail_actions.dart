part of 'collection_detail_screen.dart';

class _GroupActionStrip extends ConsumerWidget {
  const _GroupActionStrip({
    required this.collectionId,
    required this.collection,
  });

  final String collectionId;
  final CollectCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _GroupActionButton(
        icon: CollectIcons.donate,
        label: 'Contribute',
        onTap: () => context.go('/groups/$collectionId/contribute'),
      ),
      _GroupActionButton(
        icon: CollectIcons.ledger,
        label: 'Activity',
        onTap: () => context.go('/groups/$collectionId/ledger'),
      ),
      _GroupActionButton(
        icon: CollectIcons.qr,
        label: 'Group QR',
        onTap: () => context.go('/groups/$collectionId/share'),
      ),
      _GroupActionButton(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => shareGroupDeepLink(
          context: context,
          ref: ref,
          collection: collection,
        ),
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: actions.length,
        separatorBuilder: (_, _) => CollectSpacing.gapW12,
        itemBuilder: (context, index) => actions[index],
      ),
    );
  }
}

class _GroupActionButton extends StatelessWidget {
  const _GroupActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final fill = isDark
        ? CollectColors.referenceAssetNavy.withValues(alpha: 0.90)
        : colors.glassControl;
    final border = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.14)
        : colors.glassBorder;
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        width: 76,
        child: InkWell(
          borderRadius: CollectRadius.panelBorder,
          onTap: onTap,
          child: Tooltip(
            message: label,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Material(
                  color: fill,
                  shape: const CircleBorder(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadowPaint.withValues(
                            alpha: isDark ? 0.18 : 0.08,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: SizedBox.square(
                      dimension: 52,
                      child: Icon(icon, color: foreground, size: 24),
                    ),
                  ),
                ),
                CollectSpacing.gap8,
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupMomentumRail extends StatelessWidget {
  const _GroupMomentumRail({
    required this.collection,
    required this.summary,
    required this.visibleContributionCount,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final int visibleContributionCount;

  @override
  Widget build(BuildContext context) {
    final cadence = collection.recurringCadence.trim().isEmpty
        ? 'monthly'
        : collection.recurringCadence;
    final receiverReady =
        collection.receiverMomoNumber?.trim().isNotEmpty == true;
    return CollectBentoGrid(
      dense: true,
      primary: BentoMetricCell(
        label: 'Collected',
        value: formatRwf(summary.amountRaisedRwf),
        detail:
            collection.purposeLabel ?? collection.collectionType.shortPurpose,
        icon: CollectIcons.money,
        tone: CollectStatusTone.success,
        emphasis: true,
      ),
      top: BentoMetricCell(
        label: 'Cadence',
        value: cadence,
        detail: '${summary.supporterCount} supporters',
        icon: CollectIcons.pending,
        tone: CollectStatusTone.info,
      ),
      bottom: BentoMetricCell(
        label: receiverReady ? 'Receiver ready' : 'Receiver pending',
        value: visibleContributionCount == 1
            ? '1 activity'
            : '$visibleContributionCount activities',
        detail: collection.isPublic ? 'Public link active' : 'Private group',
        icon: receiverReady ? CollectIcons.momo : CollectIcons.warning,
        tone: receiverReady
            ? CollectStatusTone.success
            : CollectStatusTone.warning,
      ),
    );
  }
}
