import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRoute(WidgetTester tester, String route) async {
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    for (var i = 0; i < 14; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'all mobile routes render on physical device without UI exceptions',
    (tester) async {
      var screenshotsEnabled = true;
      try {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      } on MissingPluginException {
        screenshotsEnabled = false;
      } on PlatformException {
        screenshotsEnabled = false;
      }

      for (final spec in _routeSpecs) {
        // Printed progress is retained in the UAT log for route-level triage.
        // ignore: avoid_print
        print('collect_route_uat:start:${spec.name}:${spec.route}');
        await pumpRoute(tester, spec.route);
        expect(tester.takeException(), isNull, reason: spec.route);
        expect(find.byType(CollectApp), findsOneWidget, reason: spec.route);
        expect(find.text('Screen not found'), findsNothing, reason: spec.route);
        expect(
          find.text('This screen is unavailable.'),
          findsNothing,
          reason: spec.route,
        );
        if (screenshotsEnabled) {
          try {
            await binding.takeScreenshot('mobile_route_${spec.name}');
          } on MissingPluginException {
            screenshotsEnabled = false;
          } on PlatformException {
            screenshotsEnabled = false;
          }
        }
        // ignore: avoid_print
        print('collect_route_uat:pass:${spec.name}:${spec.route}');
      }
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

const _routeSpecs = <_RouteSpec>[
  _RouteSpec('root-redirect', '/', 'entry'),
  _RouteSpec('auth', '/auth', 'workflow'),
  _RouteSpec('profile-edit', '/settings/profile', 'workflow'),
  _RouteSpec('home', '/home', 'primary'),
  _RouteSpec('groups', '/groups', 'primary'),
  _RouteSpec('group-create', '/groups/create', 'workflow'),
  _RouteSpec('group-scan', '/groups/scan', 'workflow'),
  _RouteSpec('group-detail', '/groups/col-church', 'workflow'),
  _RouteSpec('share', '/groups/col-church/share', 'workflow'),
  _RouteSpec('invite', '/groups/col-church/invite', 'compatibility'),
  _RouteSpec('shared-group-link', '/c/st-michel-building-fund', 'entry'),
  _RouteSpec('app-share-entry', '/app', 'compatibility'),
  _RouteSpec('app-invite-link', '/invite/038491', 'compatibility'),
  _RouteSpec('contribution', '/groups/col-church/contribute', 'workflow'),
  _RouteSpec('ledger', '/groups/col-church/ledger', 'workflow'),
  _RouteSpec('manage', '/groups/col-church/manage', 'workflow'),
  _RouteSpec('group-profile', '/groups/col-church/profile', 'workflow'),
  _RouteSpec('members', '/groups/col-church/members', 'workflow'),
  _RouteSpec('settings', '/settings', 'primary'),
  _RouteSpec('account', '/settings/account', 'utility'),
  _RouteSpec('account-delete', '/settings/account/delete', 'utility'),
  _RouteSpec('legal-privacy', '/settings/legal/privacy', 'utility'),
  _RouteSpec('legal-terms', '/settings/legal/terms', 'utility'),
];

class _RouteSpec {
  const _RouteSpec(this.name, this.route, this.routeClass);

  final String name;
  final String route;
  final String routeClass;

  bool get isProductScreen => routeClass != 'compatibility';
}
