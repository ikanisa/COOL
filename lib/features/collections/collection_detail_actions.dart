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
        iconOnly: true,
        onTap: () => context.go('/groups/$collectionId/contribute'),
      ),
      _GroupActionButton(
        icon: CollectIcons.people,
        label: 'Members',
        iconOnly: true,
        onTap: () => context.go('/groups/$collectionId/members'),
      ),
      _GroupActionButton(
        icon: CollectIcons.qr,
        label: 'Group QR',
        iconOnly: true,
        onTap: () => context.go('/groups/$collectionId/share'),
      ),
      _GroupActionButton(
        icon: CollectIcons.share,
        label: 'Share',
        iconOnly: true,
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
    this.iconOnly = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool iconOnly;
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
                if (!iconOnly) ...[
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
