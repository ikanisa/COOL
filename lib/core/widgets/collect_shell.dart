import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

class CollectShell extends StatelessWidget {
  const CollectShell({
    required this.child,
    this.currentPath,
    this.onNavigate,
    super.key,
  });

  final Widget child;
  final String? currentPath;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final path = currentPath ?? GoRouterState.of(context).uri.path;
    final showNav = !_isStandalone(path);
    return CollectBackgroundRouteScope(
      routePath: path,
      child: CollectGradientBackground(
        routePath: path,
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
                            color: CollectColors.inkPrimary.withValues(
                              alpha: 0.92,
                            ),
                            border: Border.all(
                              color: colors.onImagePrimary.withValues(
                                alpha: 0.34,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: CollectColors.inkPrimary.withValues(
                                  alpha: 0.18,
                                ),
                                blurRadius: 26,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: _CollectBottomNav(
                            selectedIndex: _selectedIndexForPath(path),
                            onDestinationSelected: (index) {
                              final destination = _paths[index];
                              final handler = onNavigate;
                              if (handler != null) {
                                handler(destination);
                                return;
                              }
                              context.go(destination);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  static const _paths = <String>['/home', '/groups', '/settings'];

  bool _isStandalone(String path) {
    return path.startsWith('/onboarding') ||
        path == '/auth' ||
        path.startsWith('/auth/');
  }

  int _selectedIndexForPath(String path) {
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
      icon: CollectIcons.people,
      selectedIcon: CollectIcons.people,
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
    final showLabels = textScale <= 1.45;
    final height = showLabels ? 76.0 : 64.0;
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
    final foreground = selected
        ? colors.onImagePrimary
        : colors.onImagePrimary.withValues(alpha: 0.72);
    final indicator = LinearGradient(
      colors: [
        colors.onImagePrimary.withValues(alpha: 0.24),
        colors.periwinklePaint.withValues(alpha: 0.34),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
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
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: selected ? 56 : 44,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? null
                        : colors.onImagePrimary.withValues(alpha: 0.04),
                    gradient: selected ? indicator : null,
                    borderRadius: CollectRadius.pillBorder,
                    border: Border.all(
                      color: colors.onImagePrimary.withValues(
                        alpha: selected ? 0.24 : 0.08,
                      ),
                    ),
                  ),
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: selected ? 22 : 21,
                    color: foreground,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 18,
                    width: double.infinity,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: selected ? 12.5 : 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        letterSpacing: 0,
                        height: 1.0,
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
