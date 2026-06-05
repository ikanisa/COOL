import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRoute(WidgetTester tester, String route) async {
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.seeded(),
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
      const routes = [
        '/onboarding',
        '/auth',
        '/auth/success',
        '/auth/failure',
        '/settings/profile',
        '/settings/readiness',
        '/permissions/sms',
        '/permissions/sms-denied',
        '/permissions/device',
        '/home',
        '/groups',
        '/groups/create',
        '/platform/iphone-create-unavailable',
        '/groups/col-church',
        '/groups/col-church/created',
        '/groups/col-church/joined',
        '/groups/join',
        '/groups/col-church/share',
        '/groups/col-church/invite',
        '/share/confirmed?message=Link%20copied',
        '/share/invalid',
        '/share/expired',
        '/groups/col-church/contribute',
        '/groups/col-church/pay/intent-render/waiting',
        '/groups/col-church/pay/intent-render/state/pending',
        '/groups/col-church/pay/intent-render/state/confirmed',
        '/groups/col-church/pay/intent-render/state/expired',
        '/groups/col-church/pay/intent-render/state/needs-review',
        '/groups/col-church/ledger',
        '/groups/col-church/owner',
        '/groups/col-church/owner/sms-health',
        '/groups/col-church/owner/receiver',
        '/groups/col-church/manage',
        '/groups/col-church/members',
        '/settings',
        '/settings/account',
        '/settings/account/delete',
        '/settings/privacy',
        '/settings/legal/privacy',
        '/settings/legal/terms',
        '/settings/help',
        '/notifications',
        '/offline',
        '/sync',
      ];

      for (final route in routes) {
        await pumpRoute(tester, route);
        expect(tester.takeException(), isNull, reason: route);
        expect(find.byType(CollectApp), findsOneWidget, reason: route);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
