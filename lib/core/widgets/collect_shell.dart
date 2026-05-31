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
                      child: NavigationBar(
                        selectedIndex: _selectedIndex(context),
                        onDestinationSelected: (index) =>
                            context.go(_paths[index]),
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(CollectIcons.homeOutline),
                            selectedIcon: Icon(CollectIcons.home),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            icon: Icon(CollectIcons.collectionsOutline),
                            selectedIcon: Icon(CollectIcons.collections),
                            label: 'Groups',
                          ),
                          NavigationDestination(
                            icon: Icon(CollectIcons.settingsOutline),
                            selectedIcon: Icon(CollectIcons.settings),
                            label: 'Settings',
                          ),
                        ],
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
