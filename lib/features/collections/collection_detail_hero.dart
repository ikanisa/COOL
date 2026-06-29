part of 'collection_detail_screen.dart';

class _GroupHero extends StatelessWidget {
  const _GroupHero({
    required this.collectionId,
    required this.collection,
    required this.summary,
    required this.canManage,
  });

  final String collectionId;
  final CollectCollection collection;
  final CollectionSummary summary;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconForeground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final iconFill = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.12)
        : colors.actionColor.withValues(alpha: 0.12);
    final iconBorder = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.18)
        : colors.actionColor.withValues(alpha: 0.20);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final titleSize = textScale > 1.25 ? 24.0 : 30.0;
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.actionColor,
      padding: EdgeInsets.zero,
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          CollectColors.referencePaymentsPurpleDeep,
          Color.alphaBlend(
            colors.actionColor.withValues(alpha: isDark ? 0.18 : 0.12),
            CollectColors.referencePaymentsPurple,
          ),
          CollectColors.referenceContentDark,
        ],
        stops: const [0, 0.54, 1],
      ),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Positioned(
              right: -42,
              top: -48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.actionColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 190, height: 190),
              ),
            ),
            Padding(
              padding: CollectSpacing.cardPaddingComfortable,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: iconFill,
                          borderRadius: CollectRadius.panelBorder,
                          border: Border.all(color: iconBorder),
                        ),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            collectionTypeIcon(collection.collectionType),
                            color: iconForeground,
                            size: 24,
                          ),
                        ),
                      ),
                      CollectSpacing.gapW12,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collection.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: colors.onImagePrimary,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                    letterSpacing: 0,
                                  ),
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                            CollectSpacing.gap8,
                            CollectionTypeBadge(
                              type: collection.collectionType,
                              compact: true,
                              iconOnly: true,
                            ),
                          ],
                        ),
                      ),
                      if (canManage) ...[
                        CollectSpacing.gapW8,
                        Semantics(
                          button: true,
                          label: 'Group settings',
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: iconFill,
                              shape: BoxShape.circle,
                              border: Border.all(color: iconBorder),
                            ),
                            child: Material(
                              color: colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    context.go('/groups/$collectionId/manage'),
                                child: SizedBox.square(
                                  dimension: 44,
                                  child: Icon(
                                    CollectIcons.settings,
                                    size: 22,
                                    color: iconForeground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  CollectSpacing.gap24,
                  _GroupStatsCard(
                    collectionId: collectionId,
                    totalRaised: summary.amountRaisedRwf,
                    participants: summary.supporterCount,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupStatsCard extends StatelessWidget {
  const _GroupStatsCard({
    required this.collectionId,
    required this.totalRaised,
    required this.participants,
  });

  final String collectionId;
  final int totalRaised;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x1),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _GroupStatMetric(
              value: formatRwf(totalRaised),
              icon: CollectIcons.money,
              tone: CollectStatusTone.success,
              primary: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x3),
            child: Container(
              width: 1,
              height: 72,
              color: colors.onImagePrimary.withValues(alpha: 0.16),
            ),
          ),
          Expanded(
            flex: 2,
            child: _GroupStatMetric(
              value: '$participants',
              icon: CollectIcons.people,
              tone: CollectStatusTone.info,
              onTap: () => context.go('/groups/$collectionId/members'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStatMetric extends StatelessWidget {
  const _GroupStatMetric({
    required this.value,
    required this.icon,
    required this.tone,
    this.primary = false,
    this.onTap,
  });

  final String value;
  final IconData icon;
  final CollectStatusTone tone;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconForeground = colors.statusForeground(tone);
    final iconFill = isDark
        ? Color.alphaBlend(
            iconForeground.withValues(alpha: 0.16),
            CollectColors.referenceContentDark,
          )
        : colors.statusBackground(tone);
    final iconBorder = iconForeground.withValues(alpha: isDark ? 0.26 : 0.18);
    final amountColor = colors.onImagePrimary;
    final metric = Column(
      crossAxisAlignment: primary
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: iconFill,
            shape: BoxShape.circle,
            border: Border.all(color: iconBorder),
          ),
          child: SizedBox.square(
            dimension: primary ? 42 : 38,
            child: Icon(icon, color: iconForeground, size: primary ? 23 : 21),
          ),
        ),
        CollectSpacing.gap8,
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: primary ? Alignment.centerLeft : Alignment.center,
          child: Text(
            value,
            style: primary
                ? CollectTypography.amountHero(amountColor)
                : CollectTypography.amountHero(iconForeground),
          ),
        ),
      ],
    );
    if (onTap == null) return metric;
    return Tooltip(
      message: 'Open group members',
      child: Semantics(
        button: true,
        label: 'Open group members',
        child: InkWell(
          borderRadius: CollectRadius.mdBorder,
          onTap: onTap,
          child: metric,
        ),
      ),
    );
  }
}
