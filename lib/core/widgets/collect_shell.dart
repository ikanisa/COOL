import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

class CollectShell extends StatelessWidget {
  const CollectShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final path = GoRouterState.of(context).uri.path;
    final showNav = !_isStandalone(path);
    return CollectGradientBackground(
      child: Scaffold(
        backgroundColor: colors.transparent,
        extendBody: true,
        body: child,
        bottomNavigationBar: showNav
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.glassControl.withValues(alpha: 0.86),
                          border: Border.all(color: colors.glassBorder),
                        ),
                        child: _CollectBottomNav(
                          selectedIndex: _selectedIndex(context),
                          onDestinationSelected: (index) =>
                              context.go(_paths[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  static const _paths = <String>['/home', '/groups', '/settings'];

  bool _isStandalone(String path) {
    return path.startsWith('/onboarding') ||
        path == '/auth' ||
        path.startsWith('/auth/');
  }

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/groups')) {
      return 1;
    }
    if (path.startsWith('/settings')) {
      return 2;
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
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = <_CollectNavDestination>[
    _CollectNavDestination(
      label: 'Home',
      icon: CollectIcons.homeOutline,
      selectedIcon: CollectIcons.home,
    ),
    _CollectNavDestination(
      label: 'Groups',
      icon: CollectIcons.collectionsOutline,
      selectedIcon: CollectIcons.collections,
    ),
    _CollectNavDestination(
      label: 'Settings',
      icon: CollectIcons.settingsOutline,
      selectedIcon: CollectIcons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final showLabels = textScale <= 1.35;
    final height = showLabels ? 68.0 : 60.0;
    return Semantics(
      container: true,
      label: 'Primary navigation',
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index += 1)
              Expanded(
                child: _CollectBottomNavItem(
                  destination: _destinations[index],
                  selected: selectedIndex == index,
                  showLabel: showLabels,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
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
    final foreground = selected ? colors.textPrimary : colors.textMuted;
    final indicator = LinearGradient(
      colors: [
        colors.actionColor.withValues(alpha: 0.22),
        colors.periwinklePaint.withValues(alpha: 0.16),
      ],
    );
    return Tooltip(
      message: destination.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? null : colors.transparent,
                    gradient: selected ? indicator : null,
                    borderRadius: BorderRadius.circular(999),
                    border: selected
                        ? Border.all(color: colors.glassBorder)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 22,
                      color: foreground,
                    ),
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 3),
                  Flexible(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0,
                      ),
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
