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
  _RouteSpec('root-redirect', '/'),
  _RouteSpec('onboarding', '/onboarding'),
  _RouteSpec('onboarding-legal', '/onboarding/legal'),
  _RouteSpec('auth', '/auth'),
  _RouteSpec('profile', '/settings/profile'),
  _RouteSpec('sms-permission-redirect', '/permissions/sms'),
  _RouteSpec('sms-denied', '/permissions/sms-denied'),
  _RouteSpec('device-permission', '/permissions/device'),
  _RouteSpec('notifications-denied', '/permissions/notifications-denied'),
  _RouteSpec('camera-denied', '/permissions/camera-denied'),
  _RouteSpec('home', '/home'),
  _RouteSpec('groups', '/groups'),
  _RouteSpec('group-create', '/groups/create'),
  _RouteSpec('group-scan', '/groups/scan'),
  _RouteSpec(
    'iphone-create-unavailable',
    '/platform/iphone-create-unavailable',
  ),
  _RouteSpec('group-detail', '/groups/col-church'),
  _RouteSpec('group-joined', '/groups/col-church/joined'),
  _RouteSpec('owner-redirect', '/groups/col-church/owner'),
  _RouteSpec(
    'owner-sms-health-redirect',
    '/groups/col-church/owner/sms-health',
  ),
  _RouteSpec('owner-receiver-redirect', '/groups/col-church/owner/receiver'),
  _RouteSpec('share', '/groups/col-church/share'),
  _RouteSpec('invite', '/groups/col-church/invite'),
  _RouteSpec('shared-group-link', '/c/st-michel-building-fund'),
  _RouteSpec('share-invalid', '/share/invalid'),
  _RouteSpec('share-expired', '/share/expired'),
  _RouteSpec('share-expired-request', '/share/expired/request'),
  _RouteSpec('share-confirmed-redirect', '/share/confirmed'),
  _RouteSpec('app-share-entry', '/app'),
  _RouteSpec('app-invite-link', '/invite/038491'),
  _RouteSpec('contribution', '/groups/col-church/contribute'),
  _RouteSpec(
    'payment-handoff-redirect',
    '/groups/col-church/pay/intent-render/handoff',
  ),
  _RouteSpec('payment-intent', '/groups/col-church/pay/intent-render'),
  _RouteSpec(
    'payment-pending',
    '/groups/col-church/pay/intent-render/state/pending',
  ),
  _RouteSpec(
    'payment-confirmed',
    '/groups/col-church/pay/intent-render/state/confirmed',
  ),
  _RouteSpec(
    'payment-expired',
    '/groups/col-church/pay/intent-render/state/expired',
  ),
  _RouteSpec(
    'payment-needs-review',
    '/groups/col-church/pay/intent-render/state/needs-review',
  ),
  _RouteSpec(
    'payment-support-review',
    '/groups/col-church/support/payment/intent-render',
  ),
  _RouteSpec('ledger', '/groups/col-church/ledger'),
  _RouteSpec('manage', '/groups/col-church/manage'),
  _RouteSpec('group-profile', '/groups/col-church/profile'),
  _RouteSpec('members', '/groups/col-church/members'),
  _RouteSpec('settings', '/settings'),
  _RouteSpec('account', '/settings/account'),
  _RouteSpec('account-delete', '/settings/account/delete'),
  _RouteSpec('privacy', '/settings/privacy'),
  _RouteSpec('legal-privacy', '/settings/legal/privacy'),
  _RouteSpec('legal-terms', '/settings/legal/terms'),
  _RouteSpec('help', '/settings/help'),
  _RouteSpec('notifications', '/notifications'),
  _RouteSpec('offline', '/offline'),
  _RouteSpec('sync', '/sync'),
];

class _RouteSpec {
  const _RouteSpec(this.name, this.route);

  final String name;
  final String route;
}
