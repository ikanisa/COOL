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
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final actionButtons = <Widget>[
      for (final action in actions)
        DecoratedBox(
          decoration: BoxDecoration(
            color: CollectRuntimeTokens.chromeControl(colors),
            shape: BoxShape.circle,
            border: Border.all(
              color: CollectRuntimeTokens.chromeControlBorder(colors),
            ),
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
            onPressed: () {
              CollectHaptics.selection();
              goBackOrHome(context);
            },
            icon: const Icon(Icons.arrow_back_rounded),
            color: foreground,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              backgroundColor: CollectRuntimeTokens.chromeControl(colors),
              side: BorderSide(
                color: CollectRuntimeTokens.chromeControlBorder(colors),
              ),
            ),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  CollectSpacing.gap4,
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: CollectRuntimeTokens.chromeMutedForeground(colors),
                      height: 1.15,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
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

class CollectChromeAction {
  const CollectChromeAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

class CollectScreenTopChrome extends StatelessWidget {
  const CollectScreenTopChrome({
    this.avatarLabel = 'C',
    this.avatarTooltip = 'Profile',
    this.searchLabel = 'Search',
    this.onAvatarTap,
    this.onSearchTap,
    this.actions = const [],
    super.key,
  });

  final String avatarLabel;
  final String avatarTooltip;
  final String searchLabel;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onSearchTap;
  final List<CollectChromeAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final muted = CollectRuntimeTokens.chromeMutedForeground(colors);
    final control = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    final trimmedAvatar = avatarLabel.trim();
    final initial = trimmedAvatar.isEmpty
        ? 'C'
        : String.fromCharCode(trimmedAvatar.runes.first).toUpperCase();
    return Semantics(
      container: true,
      label: 'Screen actions',
      child: Row(
        children: [
          Tooltip(
            message: avatarTooltip,
            child: Material(
              color: control,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAvatarTap == null
                    ? null
                    : () {
                        CollectHaptics.selection();
                        onAvatarTap!();
                      },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: border),
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: Text(
                        initial,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Tooltip(
              message: searchLabel,
              child: Material(
                color: control,
                borderRadius: CollectRadius.pillBorder,
                child: InkWell(
                  borderRadius: CollectRadius.pillBorder,
                  onTap: onSearchTap == null
                      ? null
                      : () {
                          CollectHaptics.selection();
                          onSearchTap!();
                        },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: CollectRadius.pillBorder,
                      border: Border.all(color: border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CollectSpacing.x3,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Icon(CollectIcons.search, color: muted, size: 20),
                          CollectSpacing.gapW8,
                          Expanded(
                            child: Text(
                              searchLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: muted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final action in actions.take(2)) ...[
            CollectSpacing.gapW8,
            Tooltip(
              message: action.tooltip,
              child: IconButton(
                onPressed: () {
                  CollectHaptics.selection();
                  action.onPressed();
                },
                icon: Icon(action.icon),
                color: foreground,
                style: IconButton.styleFrom(
                  fixedSize: const Size(44, 44),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  backgroundColor: control,
                  side: BorderSide(color: border),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CollectHeroQuickAction {
  const CollectHeroQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.key,
    this.tooltip,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;
}

class CollectScreenHero extends StatelessWidget {
  const CollectScreenHero({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.metric,
    this.primaryAction,
    this.quickActions = const [],
    this.icon,
    this.semanticLabel,
    this.centerGap = CollectSpacing.x8,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final String? metric;
  final Widget? primaryAction;
  final List<CollectHeroQuickAction> quickActions;
  final IconData? icon;
  final String? semanticLabel;
  final double centerGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final muted = CollectRuntimeTokens.chromeMutedForeground(colors);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final headlineSize = textScale > 1.3 ? 42.0 : 52.0;
    return Semantics(
      container: true,
      header: true,
      label:
          semanticLabel ??
          [
            if (eyebrow != null) eyebrow,
            metric ?? title,
            if (subtitle != null) subtitle,
          ].whereType<String>().join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: centerGap),
            if (icon != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: foreground.withValues(alpha: 0.16)),
                ),
                child: SizedBox.square(
                  dimension: 58,
                  child: Icon(icon, color: foreground, size: 28),
                ),
              ),
              CollectSpacing.gap16,
            ],
            if (eyebrow != null) ...[
              Text(
                eyebrow!,
                textAlign: TextAlign.center,
                style: CollectTypography.eyebrowLabel(muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              CollectSpacing.gap8,
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                metric ?? title,
                textAlign: TextAlign.center,
                style:
                    (metric == null
                            ? Theme.of(context).textTheme.displaySmall
                            : CollectTypography.amountDisplay(foreground))
                        ?.copyWith(
                          color: foreground,
                          fontSize: metric == null ? 40 : headlineSize,
                          fontWeight: FontWeight.w900,
                          height: 0.96,
                          letterSpacing: 0,
                        ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
            if (metric != null) ...[
              CollectSpacing.gap8,
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (subtitle != null) ...[
              CollectSpacing.gap8,
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (primaryAction != null) ...[
              CollectSpacing.gap20,
              primaryAction!,
            ],
            if (quickActions.isNotEmpty) ...[
              CollectSpacing.gap32,
              CollectHeroQuickActionRow(actions: quickActions),
            ],
          ],
        ),
      ),
    );
  }
}

class CollectHeroQuickActionRow extends StatelessWidget {
  const CollectHeroQuickActionRow({required this.actions, super.key});

  final List<CollectHeroQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < actions.length; index += 1) ...[
          Expanded(
            child: _CollectHeroQuickActionButton(action: actions[index]),
          ),
          if (index != actions.length - 1) CollectSpacing.gapW8,
        ],
      ],
    );
  }
}

class _CollectHeroQuickActionButton extends StatelessWidget {
  const _CollectHeroQuickActionButton({required this.action});

  final CollectHeroQuickAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final fill = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    return Semantics(
      key: action.key,
      button: true,
      label: action.label,
      child: Tooltip(
        message: action.tooltip ?? action.label,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: () {
            CollectHaptics.selection();
            action.onTap();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: SizedBox.square(
                  dimension: 54,
                  child: Icon(action.icon, color: foreground, size: 24),
                ),
              ),
              CollectSpacing.gap8,
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
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
    this.topChrome,
    this.hero,
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.onRefresh,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? topChrome;
  final Widget? hero;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final RefreshCallback? onRefresh;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final listView = ListView(
      physics: onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
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
          ScreenHeader(title: title, subtitle: subtitle, actions: actions),
        if (topChrome != null) ...[
          if (showHeader) CollectSpacing.gap20,
          topChrome!,
        ],
        if (hero != null) ...[
          compact ? CollectSpacing.gap20 : CollectSpacing.gap24,
          hero!,
        ],
        if (banner != null) ...[CollectSpacing.gap20, banner!],
        compact ? CollectSpacing.gap12 : CollectSpacing.gap24,
        ..._withGaps(
          children,
          gap: compact ? CollectSpacing.gap12 : CollectSpacing.gap16,
        ),
      ],
    );
    final scrollable = onRefresh == null
        ? listView
        : RefreshIndicator.adaptive(
            onRefresh: () async {
              CollectHaptics.lightImpact();
              await onRefresh!();
            },
            child: listView,
          );
    return CollectGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: scrollable),
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
    this.topChrome,
    this.hero,
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.onRefresh,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? topChrome;
  final Widget? hero;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final RefreshCallback? onRefresh;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      title: title,
      subtitle: subtitle,
      actions: actions,
      topChrome: topChrome,
      hero: hero,
      banner: banner,
      persistentPill: persistentPill,
      bottomAction: bottomAction,
      onRefresh: onRefresh,
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
