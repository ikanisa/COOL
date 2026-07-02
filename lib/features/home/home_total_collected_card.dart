part of 'home_screen.dart';

class _HomeTotalCollectedCard extends StatelessWidget {
  const _HomeTotalCollectedCard({
    required this.totalAmount,
    required this.contributedGroupCount,
    required this.onContributedGroupsTap,
    this.publicId,
  });

  final int totalAmount;
  final int contributedGroupCount;
  final VoidCallback onContributedGroupsTap;
  final String? publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final mutedForeground = foreground.withValues(alpha: 0.74);
    final heroGradient = isDark
        ? const LinearGradient(
            colors: [
              CollectColors.referenceAccountBlue,
              CollectColors.referenceAccountBlueDeep,
              CollectColors.referenceAccountNavyDeep,
              CollectColors.referencePaymentsPurpleDeep,
            ],
            stops: [0, 0.34, 0.74, 1],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              colors.textPrimary,
              colors.periwinklePaint,
              colors.actionColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: heroGradient,
        boxShadow: [
          BoxShadow(
            color: CollectColors.inkPrimary.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              right: -48,
              top: -58,
              child: _HomeAngledPanel(
                color: foreground.withValues(alpha: isDark ? 0.08 : 0.14),
                width: 180,
                height: 112,
                angle: -0.24,
              ),
            ),
            Positioned(
              left: -58,
              bottom: -72,
              child: _HomeAngledPanel(
                color: colors.mintPaint.withValues(alpha: 0.18),
                width: 190,
                height: 96,
                angle: 0.18,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      _HomeCollectLockup(foreground: foreground),
                      const Spacer(),
                      if (publicId != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.16),
                            borderRadius: CollectRadius.pillBorder,
                            border: Border.all(
                              color: foreground.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            child: Text(
                              publicId!,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w900,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  CollectSpacing.gap24,
                  Text(
                    'TOTAL COLLECTED',
                    style: CollectTypography.eyebrowLabel(mutedForeground),
                  ),
                  CollectSpacing.gap8,
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatRwf(totalAmount),
                      style: CollectTypography.amountDisplay(
                        foreground,
                      ).copyWith(fontSize: 52, height: 0.98),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Tooltip(
                    message: 'Supported groups',
                    child: Semantics(
                      button: true,
                      label: contributedGroupCount == 1
                          ? '1 supported group'
                          : '$contributedGroupCount supported groups',
                      child: Material(
                        color: colors.transparent,
                        borderRadius: CollectRadius.pillBorder,
                        child: InkWell(
                          key: const Key('home_supported_groups_chip'),
                          borderRadius: CollectRadius.pillBorder,
                          onTap: onContributedGroupsTap,
                          child: Ink(
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.16),
                              borderRadius: CollectRadius.pillBorder,
                              border: Border.all(
                                color: foreground.withValues(alpha: 0.12),
                              ),
                            ),
                            child: ExcludeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 9,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CollectIcons.collections,
                                      color: foreground,
                                      size: 18,
                                    ),
                                    CollectSpacing.gapW8,
                                    Text(
                                      '$contributedGroupCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: foreground,
                                            fontWeight: FontWeight.w900,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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

class _HomeCollectLockup extends StatelessWidget {
  const _HomeCollectLockup({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Collect',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: foreground.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(CollectIcons.savings, color: foreground, size: 16),
              ),
            ),
            CollectSpacing.gapW8,
            Text(
              'Collect',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAngledPanel extends StatelessWidget {
  const _HomeAngledPanel({
    required this.color,
    required this.width,
    required this.height,
    required this.angle,
  });

  final Color color;
  final double width;
  final double height;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}
