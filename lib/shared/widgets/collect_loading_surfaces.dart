part of 'collect_state_panels.dart';

class CollectEmptyState extends StatelessWidget {
  const CollectEmptyState({
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
    return CollectGradientBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: CollectSpacing.screenPadding,
            child: CollectCard(
              emphasis: CollectCardEmphasis.flat,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CollectToneIcon(
                    icon: icon,
                    tone: CollectStatusTone.info,
                    large: true,
                  ),
                  CollectSpacing.gap16,
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap8,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (action != null) ...[CollectSpacing.gap20, action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollectErrorState extends StatelessWidget {
  const CollectErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return CollectEmptyState(
      icon: CollectIcons.error,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : CollectButton(label: 'Try again', onPressed: onRetry),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    this.lines = 3,
    this.semanticsLabel = 'Loading content',
    this.showCard = true,
    super.key,
  });

  final int lines;
  final String semanticsLabel;
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final skeleton = Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: Column(
        children: [
          for (var index = 0; index < lines; index++) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.42),
                borderRadius: CollectRadius.pillBorder,
              ),
              child: SizedBox(
                height: index == 0 ? 22 : 14,
                width: double.infinity,
              ),
            ),
            if (index != lines - 1) CollectSpacing.gap12,
          ],
        ],
      ),
    );
    if (!showCard) return skeleton;
    return CollectCard(child: skeleton);
  }
}

class LoadingStatePanel extends StatelessWidget {
  const LoadingStatePanel({
    required this.title,
    required this.message,
    this.icon = CollectIcons.sync,
    this.lines = 3,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading: $title',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      CollectSpacing.gap4,
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            CollectSpacing.gap16,
            LoadingSkeleton(
              lines: lines,
              semanticsLabel: 'Loading placeholder for $title',
              showCard: false,
            ),
          ],
        ),
      ),
    );
  }
}

class CollectScreenLoadingState extends StatelessWidget {
  const CollectScreenLoadingState({
    required this.title,
    required this.message,
    this.icon = CollectIcons.sync,
    this.skeletonCount = 2,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final int skeletonCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading screen: $title',
      child: Column(
        key: ValueKey<String>('loading-$title'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoadingStatePanel(title: title, message: message, icon: icon),
          for (var index = 0; index < skeletonCount; index += 1) ...[
            CollectSpacing.gap16,
            LoadingSkeleton(
              lines: index == 0 ? 4 : 3,
              semanticsLabel: 'Loading section ${index + 1} for $title',
            ),
          ],
        ],
      ),
    );
  }
}

class CollectBottomSheet extends StatelessWidget {
  const CollectBottomSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CollectRadius.bottomSheet),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassPanel,
            border: Border.all(color: colors.glassBorder),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CollectRadius.bottomSheet),
            ),
            boxShadow: CollectShadows.card(),
          ),
          child: Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: child,
          ),
        ),
      ),
    );
  }
}
