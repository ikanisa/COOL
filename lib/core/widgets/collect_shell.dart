import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

class CollectShell extends StatelessWidget {
  const CollectShell({
    this.child,
    this.navigationShell,
    this.currentPath,
    this.onNavigate,
    super.key,
  }) : assert(
         child != null || navigationShell != null,
         'CollectShell requires either a child or a navigationShell.',
       );

  final Widget? child;
  final StatefulNavigationShell? navigationShell;
  final String? currentPath;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final path = currentPath ?? GoRouterState.of(context).uri.path;
    final showNav = !_isStandalone(path);
    final useRail = showNav && MediaQuery.sizeOf(context).width >= 720;
    final selectedIndex = navigationShell == null
        ? _selectedIndexForPath(path)
        : _destinationIndexForBranch(navigationShell!.currentIndex);
    final body = navigationShell ?? child!;
    return CollectBackdropScope(
      tone: switch (path) {
        '/home' => CollectBackdropTone.account,
        '/groups' || '/activity' => CollectBackdropTone.discovery,
        _ => CollectBackdropTone.plain,
      },
      child: CollectGradientBackground(
        child: Scaffold(
          backgroundColor: colors.transparent,
          extendBody: true,
          body: useRail
              ? Row(
                  children: [
                    _CollectNavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: _navigateToIndex,
                    ),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: showNav && !useRail
              ? SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Material(
                    key: const ValueKey('collect-floating-navigation'),
                    color: CollectColors.referenceChromeBlack,
                    shape: RoundedRectangleBorder(
                      borderRadius: CollectRadius.pillBorder,
                      side: BorderSide(
                        color: colors.onImagePrimary.withValues(
                          alpha: MediaQuery.highContrastOf(context)
                              ? 0.8
                              : 0.36,
                        ),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _CollectBottomNav(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: _navigateToIndex,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _navigateToIndex(BuildContext context, int index) {
    final destination = _collectNavDestinations[index];
    CollectHaptics.selection();
    final handler = onNavigate;
    if (handler != null) {
      handler(destination.path);
      return;
    }
    final statefulShell = navigationShell;
    if (statefulShell != null) {
      statefulShell.goBranch(
        destination.branchIndex,
        initialLocation: destination.branchIndex == statefulShell.currentIndex,
      );
      return;
    }
    context.go(destination.path);
  }

  bool _isStandalone(String path) {
    return path == '/' ||
        path == '/auth' ||
        path.startsWith('/auth/') ||
        path == '/groups/create' ||
        path == '/groups/scan' ||
        (path.startsWith('/groups/') && path.endsWith('/contribute')) ||
        path.contains('/share') ||
        path == '/settings/notifications' ||
        path == '/settings/appearance' ||
        path == '/settings/security' ||
        path == '/settings/help' ||
        path == '/settings/account/delete' ||
        path.startsWith('/settings/legal/');
  }

  int? _selectedIndexForPath(String path) {
    if (path.startsWith('/groups')) {
      return 1;
    }
    if (path.startsWith('/settings')) {
      return 3;
    }
    if (path.startsWith('/contribute')) {
      return null;
    }
    if (path.startsWith('/activity')) {
      return 2;
    }
    return 0;
  }

  int? _destinationIndexForBranch(int branchIndex) {
    final index = _collectNavDestinations.indexWhere(
      (destination) => destination.branchIndex == branchIndex,
    );
    return index < 0 ? null : index;
  }
}

class _CollectBottomNav extends StatelessWidget {
  const _CollectBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int? selectedIndex;
  final void Function(BuildContext context, int index) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final showLabels = textScale <= 1.3;
    final height = showLabels
        ? 60.0 + 14 * (textScale - 1).clamp(0, 0.3)
        : 52.0;
    return Semantics(
      container: true,
      label: 'Primary navigation',
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              var index = 0;
              index < _collectNavDestinations.length;
              index += 1
            )
              Expanded(
                child: _CollectBottomNavItem(
                  destination: _collectNavDestinations[index],
                  selected: selectedIndex == index,
                  showLabel: showLabels,
                  onTap: () => onDestinationSelected(context, index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollectNavigationRail extends StatelessWidget {
  const _CollectNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int? selectedIndex;
  final void Function(BuildContext context, int index) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SafeArea(
      right: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CollectColors.referenceChromeBlack,
          border: Border(
            right: BorderSide(
              color: colors.onImagePrimary.withValues(alpha: 0.10),
            ),
          ),
        ),
        child: Semantics(
          container: true,
          label: 'Primary navigation rail',
          child: NavigationRail(
            backgroundColor: colors.transparent,
            selectedIndex: selectedIndex,
            minWidth: 88,
            minExtendedWidth: 128,
            labelType: NavigationRailLabelType.all,
            useIndicator: false,
            selectedIconTheme: IconThemeData(
              color: colors.onImagePrimary,
              size: 24,
            ),
            unselectedIconTheme: IconThemeData(
              color: colors.onImagePrimary.withValues(alpha: 0.60),
              size: 22,
            ),
            selectedLabelTextStyle: Theme.of(context).textTheme.labelMedium
                ?.copyWith(
                  color: colors.onImagePrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
            unselectedLabelTextStyle: Theme.of(context).textTheme.labelMedium
                ?.copyWith(
                  color: colors.onImagePrimary.withValues(alpha: 0.60),
                  fontWeight: CollectTypography.weightMedium,
                ),
            onDestinationSelected: (index) =>
                onDestinationSelected(context, index),
            destinations: [
              for (final destination in _collectNavDestinations)
                NavigationRailDestination(
                  icon: Tooltip(
                    message: destination.label,
                    child: Icon(destination.icon),
                  ),
                  selectedIcon: Tooltip(
                    message: destination.label,
                    child: Icon(destination.selectedIcon),
                  ),
                  label: Text(destination.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectBottomNavItem extends StatelessWidget {
  const _CollectBottomNavItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final _CollectNavDestination destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? colors.onImagePrimary
        : colors.onImagePrimary.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          child: AnimatedContainer(
            key: ValueKey('collect-nav-${destination.label.toLowerCase()}'),
            duration: CollectMotion.duration(context, CollectMotion.fast),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? colors.onImagePrimary.withValues(alpha: 0.14)
                  : colors.transparent,
              borderRadius: CollectRadius.pillBorder,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: selected ? 23 : 21,
                  color: foreground,
                ),
                if (showLabel) ...[
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 14 * MediaQuery.textScalerOf(context).scale(1),
                    width: double.infinity,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: selected
                            ? CollectTypography.sizeNavigationSelected
                            : CollectTypography.sizeNavigation,
                        fontWeight: selected
                            ? CollectTypography.weightBold
                            : CollectTypography.weightMedium,
                        letterSpacing: CollectTypography.trackingDefault,
                        height: CollectTypography.leadingSolid,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _collectNavDestinations = <_CollectNavDestination>[
  _CollectNavDestination(
    label: 'Home',
    icon: CollectIcons.homeOutline,
    selectedIcon: CollectIcons.home,
    path: '/home',
    branchIndex: 0,
  ),
  _CollectNavDestination(
    label: 'Groups',
    icon: CollectIcons.people,
    selectedIcon: CollectIcons.people,
    path: '/groups',
    branchIndex: 1,
  ),
  _CollectNavDestination(
    label: 'Activity',
    icon: CollectIcons.activity,
    selectedIcon: CollectIcons.activity,
    path: '/activity',
    branchIndex: 3,
  ),
  _CollectNavDestination(
    label: 'Profile',
    icon: CollectIcons.profile,
    selectedIcon: CollectIcons.profile,
    path: '/settings',
    branchIndex: 4,
  ),
];

class _CollectNavDestination {
  const _CollectNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.branchIndex,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final int branchIndex;
}
