part of 'collect_components.dart';

class CollectVisualFeatureCard extends StatelessWidget {
  const CollectVisualFeatureCard({
    required this.asset,
    required this.title,
    required this.message,
    required this.icon,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final panelGradient = isDark
        ? LinearGradient(
            colors: [
              CollectColors.referencePaymentsPurpleDeep,
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.16),
                CollectColors.referencePaymentsPurple,
              ),
              CollectColors.referenceAssetNavy,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.14),
                colors.glassPanel,
              ),
              Color.alphaBlend(
                colors.mintPaint.withValues(alpha: 0.08),
                colors.glassPanel,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    Widget featureImage = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    if (isDark) {
      featureImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          CollectColors.referencePaymentsPurpleDeep.withValues(alpha: 0.46),
          BlendMode.multiply,
        ),
        child: featureImage,
      );
    }
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: panelGradient,
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.48,
                    heightFactor: 1,
                    child: featureImage,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (isDark
                                ? CollectColors.referencePaymentsPurpleDeep
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.98 : 0.98),
                        (isDark
                                ? CollectColors.referencePaymentsPurple
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.88 : 0.88),
                        (isDark
                                ? CollectColors.referenceAssetNavy
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.30 : 0.18),
                      ],
                      stops: const [0, 0.58, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: CollectSpacing.cardPaddingComfortable,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CollectToneIcon(icon: icon, tone: tone),
                      CollectSpacing.gap16,
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                      CollectSpacing.gap8,
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground.withValues(alpha: 0.76),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

class CollectListTile extends StatelessWidget {
  const CollectListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final visibleSubtitle = _compactDataSubtitle(subtitle);
    return InkWell(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (visibleSubtitle != null) ...[
                    CollectSpacing.gap4,
                    Text(
                      visibleSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null || onTap != null) ...[
              CollectSpacing.gapW12,
              trailing ?? Icon(CollectIcons.chevron, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

String? _compactDataSubtitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  if (text.length > 28) return null;
  if (text.startsWith('#') ||
      text.startsWith('+') ||
      text.startsWith('RWF') ||
      text.contains('MoMo')) {
    return text;
  }
  return null;
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
                    maxLines: 1,
                    softWrap: false,
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
