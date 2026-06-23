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
        tooltip: 'Contribute',
        onTap: () => context.go('/groups/$collectionId/contribute'),
      ),
      _GroupActionButton(
        icon: CollectIcons.ledger,
        tooltip: 'Activity',
        onTap: () => context.go('/groups/$collectionId/ledger'),
      ),
      _GroupActionButton(
        icon: CollectIcons.qr,
        tooltip: 'Group QR',
        onTap: () => context.go('/groups/$collectionId/share'),
      ),
      _GroupActionButton(
        icon: CollectIcons.share,
        tooltip: 'Share',
        onTap: () => shareGroupDeepLink(
          context: context,
          ref: ref,
          collection: collection,
        ),
      ),
    ];

    return SizedBox(
      height: 64,
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
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
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
                dimension: 64,
                child: Icon(icon, color: foreground, size: 27),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
