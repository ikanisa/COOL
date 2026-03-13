import 'package:cool_app/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('shell quick actions switch branches without pushing', (
    tester,
  ) async {
    final router = _buildRouter('/groups');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Groups'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('standalone quick actions push so users can return', (
    tester,
  ) async {
    final router = _buildRouter('/momo');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('MoMo'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });
}

GoRouter _buildRouter(String targetRoute) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            Scaffold(body: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) =>
                    _LauncherScreen(route: targetRoute),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.groups,
                builder: (context, state) => const _MarkerScreen('Groups'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.momo,
        builder: (context, state) => const _MarkerScreen('MoMo'),
      ),
    ],
  );
}

class _LauncherScreen extends StatelessWidget {
  const _LauncherScreen({required this.route});

  final String route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => openQuickActionRoute(context, route),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

class _MarkerScreen extends StatelessWidget {
  const _MarkerScreen(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}
