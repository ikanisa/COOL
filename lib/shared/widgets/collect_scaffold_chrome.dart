part of 'collect_chrome.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = context.collectColors.onImagePrimary;
    final actionButtons = <Widget>[
      for (final action in actions)
        DecoratedBox(
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: foreground.withValues(alpha: 0.16)),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  fixedSize: const Size(42, 42),
                  minimumSize: const Size(42, 42),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: foreground,
                ),
              ),
              child: SizedBox.square(
                dimension: 42,
                child: Center(child: action),
              ),
            ),
          ),
        ),
    ];
    return Semantics(
      container: true,
      header: true,
      label: title,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: foreground,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              backgroundColor: foreground.withValues(alpha: 0.10),
              side: BorderSide(color: foreground.withValues(alpha: 0.16)),
            ),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.headlineSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: 0,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                ),
                if (subtitle != null) ...[
                  CollectSpacing.gap4,
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.70),
                      height: 1.15,
                      letterSpacing: 0,
                    ),
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ],
            ),
          ),
          for (final action in actionButtons) ...[CollectSpacing.gapW8, action],
        ],
      ),
    );
  }
}

class CollectPlainPageHeader extends StatelessWidget {
  const CollectPlainPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(title: title, subtitle: subtitle, actions: actions);
  }
}

class CollectGradientBackground extends StatelessWidget {
  const CollectGradientBackground({
    required this.child,
    this.routePath,
    super.key,
  });

  final Widget child;
  final String? routePath;

  @override
  Widget build(BuildContext context) {
    String? path = routePath;
    path ??= CollectBackgroundRouteScope.maybeOf(context);
    if (path == null) {
      try {
        path = GoRouterState.of(context).uri.path;
      } catch (_) {
        path = null;
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: context.collectColors.screenGradientForPath(path),
      ),
      child: child,
    );
  }
}

class CollectBackgroundRouteScope extends InheritedWidget {
  const CollectBackgroundRouteScope({
    required this.routePath,
    required super.child,
    super.key,
  });

  final String routePath;

  static String? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CollectBackgroundRouteScope>()
        ?.routePath;
  }

  @override
  bool updateShouldNotify(CollectBackgroundRouteScope oldWidget) {
    return oldWidget.routePath != routePath;
  }
}

class PremiumScaffold extends StatelessWidget {
  const PremiumScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CollectGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: CollectSpacing.screenPadding.copyWith(
                  bottom: bottomAction == null
                      ? CollectSpacing.screenCompact + 112
                      : CollectSpacing.x3,
                ),
                children: [
                  if (persistentPill != null) ...[
                    persistentPill!,
                    compact ? CollectSpacing.gap12 : CollectSpacing.gap20,
                  ],
                  if (showHeader)
                    ScreenHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                  if (banner != null) ...[CollectSpacing.gap20, banner!],
                  compact ? CollectSpacing.gap12 : CollectSpacing.gap24,
                  ..._withGaps(
                    children,
                    gap: compact ? CollectSpacing.gap12 : CollectSpacing.gap16,
                  ),
                ],
              ),
            ),
            if (bottomAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CollectSpacing.x4,
                  CollectSpacing.x2,
                  CollectSpacing.x4,
                  CollectSpacing.x4,
                ),
                child: bottomAction!,
              ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _withGaps(List<Widget> children, {required Widget gap}) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      spaced.add(children[index]);
      if (index != children.length - 1) spaced.add(gap);
    }
    return spaced;
  }
}

class ScreenScaffoldLayout extends StatelessWidget {
  const ScreenScaffoldLayout({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      title: title,
      subtitle: subtitle,
      actions: actions,
      banner: banner,
      persistentPill: persistentPill,
      bottomAction: bottomAction,
      showHeader: showHeader,
      compact: compact,
      children: children,
    );
  }
}

void goBackOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}
