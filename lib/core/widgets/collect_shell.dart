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
    return Scaffold(
      body: child,
      bottomNavigationBar: showNav
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised.withValues(alpha: 0.84),
                        border: Border.all(
                          color: colors.border.withValues(alpha: 0.72),
                        ),
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
    );
  }

  static const _paths = <String>['/home', '/groups', '/settings'];

  bool _isStandalone(String path) {
    return path == '/onboarding' ||
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
    final height = showLabels ? 66.0 : 58.0;
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
    final indicator = colors.actionCrimson.withValues(alpha: 0.18);
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
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? indicator : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
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

class CollectPlaceholderScreen extends StatelessWidget {
  const CollectPlaceholderScreen({
    required this.title,
    required this.description,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: CollectSpacing.screenPadding,
        children: [
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                CollectSpacing.gap12,
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (actions.isNotEmpty) ...[
                  CollectSpacing.gap24,
                  Wrap(
                    spacing: CollectSpacing.x3,
                    runSpacing: CollectSpacing.x3,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
