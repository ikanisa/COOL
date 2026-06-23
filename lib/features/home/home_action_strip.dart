part of 'home_screen.dart';

class _HomeActionStrip extends ConsumerWidget {
  const _HomeActionStrip({required this.onCreate, required this.showCreate});

  final VoidCallback onCreate;
  final bool showCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      if (showCreate)
        _HomeActionItem(
          icon: CollectIcons.add,
          label: 'Create',
          onTap: onCreate,
        ),
      _HomeActionItem(
        icon: CollectIcons.people,
        label: 'Join',
        onTap: () => context.go('/groups/join'),
      ),
      _HomeActionItem(
        icon: CollectIcons.qr,
        label: 'Scan QR',
        onTap: () => context.go('/groups/scan'),
      ),
      _HomeActionItem(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => shareCollectApp(context: context, ref: ref),
      ),
    ];

    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: textScale > 1.6 ? 124 : (textScale > 1.3 ? 116 : 78),
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1) CollectSpacing.gapW8,
          ],
        ],
      ),
    );
  }
}

class _HomeActionItem extends StatelessWidget {
  const _HomeActionItem({
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
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final iconFill = isDark
        ? CollectColors.inkPrimary.withValues(alpha: 0.92)
        : colors.textPrimary.withValues(alpha: 0.88);
    final iconBorder = foreground.withValues(alpha: isDark ? 0.22 : 0.20);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: iconBorder),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(icon, color: foreground, size: 23),
                ),
              ),
              SizedBox(height: textScale > 1.3 ? 4 : 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: textScale > 1.3 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
