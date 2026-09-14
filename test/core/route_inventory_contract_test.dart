import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Set<String> _registeredPaths(List<RouteBase> routes, [String parent = '']) {
  final paths = <String>{};
  for (final route in routes) {
    var path = parent;
    if (route is GoRoute) {
      path = route.path.startsWith('/')
          ? route.path
          : '${parent == '/' ? '' : parent}/${route.path}';
      paths.add(path);
    }
    paths.addAll(_registeredPaths(route.routes, path));
  }
  return paths;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('member QA catalogue covers every registered route and alias', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    expect(
      collectRoutePaths.toSet(),
      _registeredPaths(router.configuration.routes),
    );
    expect(collectRoutePaths.toSet().length, collectRoutePaths.length);
  });

  test(
    'Admin QA catalogue includes helper-generated list and detail routes',
    () {
      final container = ProviderContainer(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(adminRouterProvider);
      addTearDown(router.dispose);

      final registered = _registeredPaths(
        router.configuration.routes,
      ).where((path) => path == '/admin' || path.startsWith('/admin/')).toSet();
      expect(adminRoutePaths.toSet(), registered);
      expect(adminRoutePaths.toSet().length, adminRoutePaths.length);
    },
  );
}
