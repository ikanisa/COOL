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
    final selectedIndex =
        navigationShell?.currentIndex ?? _selectedIndexForPath(path);
    final body = navigationShell ?? child!;
    return CollectGradientBackground(
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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CollectColors.referenceChromeBlack,
                    border: Border(
                      top: BorderSide(
                        color: colors.onImagePrimary.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  child: _CollectBottomNav(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: _navigateToIndex,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  static const _paths = <String>[
    '/home',
    '/groups',
    '/contribute',
    '/activity',
    '/settings',
  ];

  void _navigateToIndex(BuildContext context, int index) {
    final destination = _paths[index];
    CollectHaptics.selection();
    final handler = onNavigate;
    if (handler != null) {
      handler(destination);
      return;
    }
    final statefulShell = navigationShell;
    if (statefulShell != null) {
      statefulShell.goBranch(
        index,
        initialLocation: index == statefulShell.currentIndex,
      );
      return;
    }
    context.go(destination);
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

  int _selectedIndexForPath(String path) {
    if (path.startsWith('/groups')) {
      return 1;
    }
    if (path.startsWith('/settings')) {
      return 4;
    }
    if (path.startsWith('/contribute')) {
      return 2;
    }
    if (path.startsWith('/activity')) {
      return 3;
    }
    return 0;
  }
}

class _CollectBottomNav extends StatelessWidget {
  const _CollectBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final void Function(BuildContext context, int index) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final showLabels = textScale <= 1.45;
    final height = showLabels ? 60.0 : 52.0;
    return Semantics(
      container: true,
      label: 'Primary navigation',
      child: SizedBox(
        height: height,
        child: Row(
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

  final int selectedIndex;
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
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
                    height: 14,
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
  ),
  _CollectNavDestination(
    label: 'Groups',
    icon: CollectIcons.people,
    selectedIcon: CollectIcons.people,
  ),
  _CollectNavDestination(
    label: 'Contribute',
    icon: CollectIcons.donate,
    selectedIcon: CollectIcons.money,
  ),
  _CollectNavDestination(
    label: 'Activity',
    icon: CollectIcons.activity,
    selectedIcon: CollectIcons.ledger,
  ),
  _CollectNavDestination(
    label: 'Profile',
    icon: CollectIcons.settingsOutline,
    selectedIcon: CollectIcons.profile,
  ),
];

class _CollectNavDestination {
  const _CollectNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
