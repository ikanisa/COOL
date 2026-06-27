import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_motion.dart';
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
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: CollectColors.referenceChromeBlack
                                .withValues(alpha: 0.94),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colors.onImagePrimary.withValues(alpha: 0.08),
                                CollectColors.inkPrimary.withValues(
                                  alpha: 0.92,
                                ),
                                CollectColors.referenceChromeBlack.withValues(
                                  alpha: 0.98,
                                ),
                              ],
                            ),
                            border: Border.all(
                              color: colors.onImagePrimary.withValues(
                                alpha: 0.44,
                              ),
                              width: 1.15,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: CollectColors.inkPrimary.withValues(
                                  alpha: 0.32,
                                ),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
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
    return path == '/' ||
        path.startsWith('/onboarding') ||
        path == '/auth' ||
        path.startsWith('/auth/') ||
        path == '/groups/create' ||
        path == '/groups/scan' ||
        path.contains('/contribute') ||
        path.contains('/pay/') ||
        path.contains('/support/payment/') ||
        path.contains('/share') ||
        path.startsWith('/permissions/') ||
        path.startsWith('/platform/') ||
        path == '/settings/account/delete' ||
        path.startsWith('/settings/legal/');
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
    final height = showLabels ? 78.0 : 66.0;
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
    return Semantics(
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
                duration: CollectMotion.duration(context, CollectMotion.medium),
                curve: CollectMotion.standard,
                width: selected ? 74 : 46,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? null
                      : colors.onImagePrimary.withValues(alpha: 0.025),
                  gradient: selected ? indicator : null,
                  borderRadius: CollectRadius.pillBorder,
                  border: Border.all(
                    color: colors.onImagePrimary.withValues(
                      alpha: selected ? 0.28 : 0.05,
                    ),
                  ),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: selected ? 23 : 21,
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
                    overflow: TextOverflow.clip,
                    style: textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontSize: selected ? 12.5 : 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
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
