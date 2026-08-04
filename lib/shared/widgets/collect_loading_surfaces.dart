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
  }) : _variant = _LoadingSkeletonVariant.lines;

  const LoadingSkeleton.card({
    this.semanticsLabel = 'Loading card',
    this.showCard = true,
    super.key,
  }) : lines = 4,
       _variant = _LoadingSkeletonVariant.card;

  const LoadingSkeleton.heroAmount({
    this.semanticsLabel = 'Loading amount',
    this.showCard = true,
    super.key,
  }) : lines = 3,
       _variant = _LoadingSkeletonVariant.heroAmount;

  const LoadingSkeleton.groupCard({
    this.semanticsLabel = 'Loading group',
    this.showCard = true,
    super.key,
  }) : lines = 4,
       _variant = _LoadingSkeletonVariant.groupCard;

  const LoadingSkeleton.ledgerRow({
    this.semanticsLabel = 'Loading ledger row',
    this.showCard = true,
    super.key,
  }) : lines = 2,
       _variant = _LoadingSkeletonVariant.ledgerRow;

  const LoadingSkeleton.actionTile({
    this.semanticsLabel = 'Loading action',
    this.showCard = true,
    super.key,
  }) : lines = 2,
       _variant = _LoadingSkeletonVariant.actionTile;

  const LoadingSkeleton.button({
    this.semanticsLabel = 'Loading button',
    this.showCard = false,
    super.key,
  }) : lines = 1,
       _variant = _LoadingSkeletonVariant.button;

  const LoadingSkeleton.formField({
    this.semanticsLabel = 'Loading form field',
    this.showCard = false,
    super.key,
  }) : lines = 2,
       _variant = _LoadingSkeletonVariant.formField;

  const LoadingSkeleton.bottomSheet({
    this.semanticsLabel = 'Loading sheet',
    this.showCard = false,
    super.key,
  }) : lines = 4,
       _variant = _LoadingSkeletonVariant.bottomSheet;

  final int lines;
  final String semanticsLabel;
  final bool showCard;
  final _LoadingSkeletonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final skeleton = Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: _skeletonForVariant(context),
    );
    if (!showCard) return skeleton;
    return CollectCard(child: skeleton);
  }

  Widget _skeletonForVariant(BuildContext context) {
    return switch (_variant) {
      _LoadingSkeletonVariant.lines => _LineSkeleton(lines: lines),
      _LoadingSkeletonVariant.card => const _CardSkeleton(),
      _LoadingSkeletonVariant.heroAmount => const _HeroAmountSkeleton(),
      _LoadingSkeletonVariant.groupCard => const _GroupCardSkeleton(),
      _LoadingSkeletonVariant.ledgerRow => const _LedgerRowSkeleton(),
      _LoadingSkeletonVariant.actionTile => const _ActionTileSkeleton(),
      _LoadingSkeletonVariant.button => const _ButtonSkeleton(),
      _LoadingSkeletonVariant.formField => const _FormFieldSkeleton(),
      _LoadingSkeletonVariant.bottomSheet => const _BottomSheetSkeleton(),
    };
  }
}

enum _LoadingSkeletonVariant {
  lines,
  card,
  heroAmount,
  groupCard,
  ledgerRow,
  actionTile,
  button,
  formField,
  bottomSheet,
}

class _SkeletonBone extends StatelessWidget {
  const _SkeletonBone({
    required this.height,
    this.width,
    this.borderRadius = CollectRadius.pill,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.collectColors.border.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: SizedBox(height: height, width: width ?? double.infinity),
    );
  }
}

class _LineSkeleton extends StatelessWidget {
  const _LineSkeleton({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < lines; index++) ...[
          FractionallySizedBox(
            widthFactor: index == lines - 1 ? 0.68 : 1,
            child: _SkeletonBone(height: index == 0 ? 22 : 14),
          ),
          if (index != lines - 1) CollectSpacing.gap12,
        ],
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SkeletonBone(height: 42, width: 42, borderRadius: 21),
            CollectSpacing.gapW12,
            Expanded(child: _LineSkeleton(lines: 2)),
          ],
        ),
        CollectSpacing.gap16,
        _SkeletonBone(height: 68, borderRadius: CollectRadius.card),
        CollectSpacing.gap16,
        _LineSkeleton(lines: 2),
      ],
    );
  }
}

class _HeroAmountSkeleton extends StatelessWidget {
  const _HeroAmountSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(
          widthFactor: 0.42,
          child: _SkeletonBone(height: 16),
        ),
        CollectSpacing.gap12,
        FractionallySizedBox(
          widthFactor: 0.82,
          child: _SkeletonBone(height: 44, borderRadius: CollectRadius.md),
        ),
        CollectSpacing.gap12,
        FractionallySizedBox(
          widthFactor: 0.58,
          child: _SkeletonBone(height: 14),
        ),
      ],
    );
  }
}

class _GroupCardSkeleton extends StatelessWidget {
  const _GroupCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBone(height: 116, borderRadius: CollectRadius.card),
        CollectSpacing.gap16,
        _LineSkeleton(lines: 2),
        CollectSpacing.gap16,
        Row(
          children: [
            Expanded(child: _SkeletonBone(height: 36)),
            CollectSpacing.gapW8,
            Expanded(child: _SkeletonBone(height: 36)),
            CollectSpacing.gapW8,
            Expanded(child: _SkeletonBone(height: 36)),
          ],
        ),
      ],
    );
  }
}

class _LedgerRowSkeleton extends StatelessWidget {
  const _LedgerRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _SkeletonBone(height: 40, width: 40, borderRadius: 20),
        CollectSpacing.gapW12,
        Expanded(child: _LineSkeleton(lines: 2)),
        CollectSpacing.gapW12,
        _SkeletonBone(height: 20, width: 74),
      ],
    );
  }
}

class _ActionTileSkeleton extends StatelessWidget {
  const _ActionTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SkeletonBone(height: 42, width: 42, borderRadius: 21),
          CollectSpacing.gap12,
          FractionallySizedBox(
            widthFactor: 0.66,
            child: _SkeletonBone(height: 12),
          ),
        ],
      ),
    );
  }
}

class _ButtonSkeleton extends StatelessWidget {
  const _ButtonSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonBone(height: 52, borderRadius: CollectRadius.pill);
  }
}

class _FormFieldSkeleton extends StatelessWidget {
  const _FormFieldSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(
          widthFactor: 0.34,
          child: _SkeletonBone(height: 12),
        ),
        CollectSpacing.gap8,
        _SkeletonBone(height: 56, borderRadius: CollectRadius.md),
      ],
    );
  }
}

class _BottomSheetSkeleton extends StatelessWidget {
  const _BottomSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return const CollectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FractionallySizedBox(
            widthFactor: 0.18,
            child: _SkeletonBone(height: 5),
          ),
          CollectSpacing.gap20,
          _HeroAmountSkeleton(),
          CollectSpacing.gap20,
          _ButtonSkeleton(),
        ],
      ),
    );
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
    final skeletons = _screenSkeletonsFor(title, skeletonCount);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading screen: $title. $message',
      child: Column(
        key: ValueKey<String>('loading-$title'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CollectToneIcon(icon: icon, tone: CollectStatusTone.info),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
          for (var index = 0; index < skeletons.length; index += 1) ...[
            CollectSpacing.gap16,
            skeletons[index],
          ],
        ],
      ),
    );
  }
}

List<Widget> _screenSkeletonsFor(String title, int skeletonCount) {
  final lower = title.toLowerCase();
  final planned = switch (lower) {
    final value when value.contains('home') => const <Widget>[
      LoadingSkeleton.heroAmount(semanticsLabel: 'Loading home balance'),
      LoadingSkeleton.groupCard(semanticsLabel: 'Loading home group preview'),
    ],
    final value when value.contains('groups') => const <Widget>[
      LoadingSkeleton.groupCard(semanticsLabel: 'Loading group card'),
      LoadingSkeleton.groupCard(semanticsLabel: 'Loading group card'),
    ],
    final value when value.contains('group') => const <Widget>[
      LoadingSkeleton.heroAmount(semanticsLabel: 'Loading group summary'),
      LoadingSkeleton.actionTile(semanticsLabel: 'Loading group actions'),
      LoadingSkeleton.ledgerRow(semanticsLabel: 'Loading recent contribution'),
    ],
    final value when value.contains('ledger') => const <Widget>[
      LoadingSkeleton.heroAmount(semanticsLabel: 'Loading ledger total'),
      LoadingSkeleton.ledgerRow(semanticsLabel: 'Loading ledger row'),
      LoadingSkeleton.ledgerRow(semanticsLabel: 'Loading ledger row'),
    ],
    final value when value.contains('settings') => const <Widget>[
      LoadingSkeleton.card(semanticsLabel: 'Loading account settings'),
      LoadingSkeleton.actionTile(semanticsLabel: 'Loading settings action'),
    ],
    _ => const <Widget>[],
  };
  if (planned.isNotEmpty) return planned.take(skeletonCount).toList();
  return [
    for (var index = 0; index < skeletonCount; index += 1)
      LoadingSkeleton(
        lines: index == 0 ? 4 : 3,
        semanticsLabel: 'Loading section ${index + 1} for $title',
      ),
  ];
}

class CollectAsyncStateView<T> extends StatelessWidget {
  const CollectAsyncStateView({
    required this.value,
    required this.data,
    this.loading,
    this.empty,
    this.isEmpty,
    this.onRetry,
    this.loadingTitle = 'Loading',
    this.loadingMessage = 'Refreshing this screen.',
    this.errorTitle = 'Could not load',
    this.errorMessage = 'Try again when the connection is stable.',
    this.loadingIcon = CollectIcons.sync,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) data;
  final Widget? loading;
  final Widget? empty;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onRetry;
  final String loadingTitle;
  final String loadingMessage;
  final String errorTitle;
  final String errorMessage;
  final IconData loadingIcon;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () =>
          loading ??
          LoadingStatePanel(
            title: loadingTitle,
            message: loadingMessage,
            icon: loadingIcon,
          ),
      error: (error, stackTrace) => CollectErrorState(
        title: errorTitle,
        message: errorMessage,
        onRetry: onRetry,
      ),
      data: (resolved) {
        final emptyPredicate = isEmpty;
        if (emptyPredicate != null && emptyPredicate(resolved)) {
          return empty ??
              const CollectEmptyState(
                icon: CollectIcons.info,
                title: 'Nothing here yet',
                message: 'This content will appear after it is available.',
              );
        }
        return data(context, resolved);
      },
    );
  }
}

class CollectBottomSheet extends StatelessWidget {
  const CollectBottomSheet({
    required this.child,
    this.blurBackground = true,
    super.key,
  });

  final Widget child;
  final bool blurBackground;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassPanel,
        border: Border.all(color: colors.glassBorder),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CollectRadius.bottomSheet),
        ),
        boxShadow: CollectShadows.card(),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: CollectSpacing.cardPaddingComfortable,
          child: child,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CollectRadius.bottomSheet),
      ),
      child: blurBackground
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: sheet,
            )
          : sheet,
    );
  }
}
