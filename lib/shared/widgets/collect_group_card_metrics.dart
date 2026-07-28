part of 'collect_group_cards.dart';

LinearGradient _groupCardGradient(BuildContext context, Color accent) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    final lead = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      CollectColors.referencePaymentsPurpleDeep,
    );
    final middle = Color.alphaBlend(
      colors.periwinklePaint.withValues(alpha: 0.10),
      CollectColors.referencePaymentsPurple,
    );
    final tail = Color.alphaBlend(
      colors.rosePaint.withValues(alpha: 0.08),
      CollectColors.referenceContentDark,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lead, middle, tail],
      stops: const [0, 0.54, 1],
    );
  }
  final lead = Color.alphaBlend(
    accent.withValues(alpha: 0.24),
    colors.surfaceRaised,
  );
  final middle = Color.alphaBlend(
    colors.periwinklePaint.withValues(alpha: 0.12),
    colors.surfaceRaised,
  );
  final tail = Color.alphaBlend(
    colors.rosePaint.withValues(alpha: 0.16),
    colors.surfaceRaised,
  );
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lead, middle, tail],
    stops: const [0, 0.55, 1],
  );
}

BoxDecoration _groupFooterDecoration(BuildContext context) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return BoxDecoration(
      color: CollectColors.referenceAssetNavy.withValues(alpha: 0.88),
      border: Border(
        top: BorderSide(color: colors.onImagePrimary.withValues(alpha: 0.20)),
      ),
    );
  }
  return BoxDecoration(
    color: colors.surfaceReadable.withValues(alpha: 0.88),
    border: Border(
      top: BorderSide(color: colors.textPrimary.withValues(alpha: 0.10)),
    ),
  );
}

class _GroupIconMetric extends StatelessWidget {
  const _GroupIconMetric({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metricColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactLargeText = textScale > 1.3;
    final textStyle = compactLargeText
        ? Theme.of(context).textTheme.labelMedium?.copyWith(
            color: metricColor,
            fontWeight: CollectTypography.weightBold,
          )
        : Theme.of(context).textTheme.titleSmall?.copyWith(
            color: metricColor,
            fontWeight: CollectTypography.weightBold,
          );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: compactLargeText ? 18 : 22),
            SizedBox(height: compactLargeText ? 2 : CollectSpacing.x1),
            Text(
              value,
              style: textStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMetaIconRow extends StatelessWidget {
  const _GroupMetaIconRow({
    required this.collection,
    required this.summary,
    required this.accent,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      label:
          '${collection.collectionType.label}, ${summary.supporterCount} members, ${collection.isPublic ? 'public' : 'private'}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GroupMetaIcon(
              icon: collectionTypeIcon(collection.collectionType),
              color: accent,
            ),
            CollectSpacing.gapW8,
            _GroupMetaIcon(icon: CollectSemanticIcons.forKeyword('members')),
            CollectSpacing.gapW4,
            Text(
              '${summary.supporterCount}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: CollectTypography.weightSemibold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            CollectSpacing.gapW8,
            _GroupMetaIcon(
              icon: collection.isPublic
                  ? CollectSemanticIcons.forKeyword('public')
                  : CollectSemanticIcons.forKeyword('private'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMetaIcon extends StatelessWidget {
  const _GroupMetaIcon({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Icon(icon, size: 15, color: color ?? colors.textMuted);
  }
}
