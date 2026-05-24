import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

class CollectShell extends StatelessWidget {
  const CollectShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex(context),
          onDestinationSelected: (index) => context.go(_paths[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(CollectIcons.homeOutline),
              selectedIcon: Icon(CollectIcons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(CollectIcons.collectionsOutline),
              selectedIcon: Icon(CollectIcons.collections),
              label: 'Goals',
            ),
            NavigationDestination(
              icon: Icon(CollectIcons.publicOutline),
              selectedIcon: Icon(CollectIcons.public),
              label: 'Public',
            ),
            NavigationDestination(
              icon: Icon(CollectIcons.settingsOutline),
              selectedIcon: Icon(CollectIcons.settings),
              label: 'Control',
            ),
          ],
        ),
      ),
    );
  }

  static const _paths = <String>[
    '/home',
    '/collections',
    '/public',
    '/settings',
  ];

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/collections')) {
      return 1;
    }
    if (path.startsWith('/public')) {
      return 2;
    }
    if (path.startsWith('/settings')) {
      return 3;
    }
    return 0;
  }
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
