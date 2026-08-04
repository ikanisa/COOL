part of 'collect_state_panels.dart';

class MinimalStatePanel extends StatelessWidget {
  const MinimalStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CollectStatusTone.info,
    this.primaryAction,
    this.secondaryAction,
    this.titleMaxLines = 2,
    this.messageMaxLines = 3,
    this.contentMaxWidth = 250,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final CollectStatusTone tone;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final int titleMaxLines;
  final int messageMaxLines;
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.tonal,
      accentColor: colors.statusForeground(tone),
      child: Semantics(
        container: true,
        label: message.trim().isEmpty ? title : '$title, $message',
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectToneIcon(icon: icon, tone: tone, large: true),
              CollectSpacing.gap16,
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
                maxLines: titleMaxLines,
              ),
              if (message.trim().isNotEmpty) ...[
                CollectSpacing.gap8,
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                  maxLines: messageMaxLines,
                ),
              ],
              if (primaryAction != null || secondaryAction != null) ...[
                CollectSpacing.gap20,
                ?primaryAction,
                if (secondaryAction != null) ...[
                  CollectSpacing.gap12,
                  secondaryAction!,
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptySearchState extends StatelessWidget {
  const EmptySearchState({
    required this.title,
    required this.message,
    this.onClear,
    this.clearLabel = 'Clear search',
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    return MinimalStatePanel(
      icon: CollectIcons.search,
      title: title,
      message: message,
      tone: CollectStatusTone.neutral,
      primaryAction: onClear == null
          ? null
          : CollectButton(
              label: clearLabel,
              icon: CollectIcons.sync,
              onPressed: onClear,
              expand: true,
            ),
    );
  }
}
