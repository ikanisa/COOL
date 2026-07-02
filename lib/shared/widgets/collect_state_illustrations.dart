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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final scrimBase = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : colors.textPrimary;
    final stateImage = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: [
            colors.statusForeground(tone).withValues(alpha: 0.58),
            colors.periwinklePaint.withValues(alpha: 0.28),
            scrimBase.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: foreground.withValues(alpha: isDark ? 0.18 : 0.14),
          size: 92,
        ),
      ),
    );
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            colors.statusForeground(tone).withValues(alpha: 0.28),
            scrimBase,
          ),
          Color.alphaBlend(
            colors.periwinklePaint.withValues(alpha: 0.24),
            CollectColors.referencePaymentsPurple,
          ),
          CollectColors.referenceAssetNavy,
        ],
      ),
      child: Semantics(
        container: true,
        label: message.trim().isEmpty ? title : '$title, $message',
        child: ClipRRect(
          borderRadius: CollectRadius.cardLargeBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 156),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.48,
                      heightFactor: 1,
                      child: stateImage,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scrimBase.withValues(alpha: isDark ? 0.98 : 0.98),
                          scrimBase.withValues(alpha: isDark ? 0.84 : 0.82),
                          scrimBase.withValues(alpha: isDark ? 0.26 : 0.20),
                        ],
                        stops: const [0, 0.56, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: CollectSpacing.cardPaddingComfortable,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CollectToneIcon(icon: icon, tone: tone, large: true),
                        CollectSpacing.gap16,
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: titleMaxLines,
                          softWrap: true,
                          overflow: TextOverflow.clip,
                        ),
                        if (message.trim().isNotEmpty) ...[
                          CollectSpacing.gap8,
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.76),
                                ),
                            maxLines: messageMaxLines,
                            softWrap: true,
                            overflow: TextOverflow.clip,
                          ),
                        ],
                        if (primaryAction != null ||
                            secondaryAction != null) ...[
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
              ],
            ),
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
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onClear;

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
              label: 'Clear search',
              icon: CollectIcons.sync,
              onPressed: onClear,
              expand: true,
            ),
    );
  }
}
