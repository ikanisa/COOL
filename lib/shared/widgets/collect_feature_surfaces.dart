part of 'collect_components.dart';

class CollectVisualFeatureCard extends StatelessWidget {
  const CollectVisualFeatureCard({
    required this.title,
    required this.message,
    required this.icon,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.tonal,
      accentColor: colors.statusForeground(tone),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                  maxLines: 2,
                ),
                CollectSpacing.gap4,
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: CollectTypography.leadingLabel,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CollectListTile extends StatelessWidget {
  const CollectListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleMaxLines = 2,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final visibleSubtitle = _visibleSubtitle(subtitle);
    return Semantics(
      container: true,
      button: onTap != null,
      enabled: onTap != null,
      label: visibleSubtitle == null ? title : '$title, $visibleSubtitle',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: CollectRadius.mdBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
            child: Row(
              children: [
                if (leading != null) ...[
                  CollectToneIcon(icon: leading!, tone: CollectStatusTone.info),
                  CollectSpacing.gapW12,
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (visibleSubtitle != null) ...[
                        CollectSpacing.gap4,
                        Text(
                          visibleSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null || onTap != null) ...[
                  CollectSpacing.gapW12,
                  trailing ??
                      Icon(CollectIcons.chevron, color: colors.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _visibleSubtitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

class EmptyIllustrationState extends StatelessWidget {
  const EmptyIllustrationState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title. $message',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x4,
          vertical: CollectSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CollectToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: MediaQuery.textScalerOf(context).scale(1) >= 1.3
                        ? 3
                        : 1,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              CollectSpacing.gap12,
              SizedBox(width: double.infinity, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}
