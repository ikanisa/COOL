part of 'payment_status_screens.dart';

class _PaymentStatusHero extends StatelessWidget {
  const _PaymentStatusHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: context.collectColors.statusForeground(tone),
      child: textScale > 1.3
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectStatusChip(label: title, tone: tone, icon: icon),
                CollectSpacing.gap8,
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectStatusChip(label: title, tone: tone, icon: icon),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
    );
  }
}

CollectCollection? _safeCollection(WidgetRef ref, String collectionId) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .maybeCollectionById(collectionId);
}

IconData _iconForTone(CollectStatusTone tone) {
  return switch (tone) {
    CollectStatusTone.success => CollectIcons.check,
    CollectStatusTone.warning => CollectIcons.warning,
    CollectStatusTone.danger => CollectIcons.error,
    CollectStatusTone.privacy => CollectIcons.privacy,
    CollectStatusTone.info => CollectIcons.info,
    CollectStatusTone.neutral => CollectIcons.info,
  };
}
