import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_licenses_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_licenses_page.dart';
import 'package:collect_app/features/settings/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';
import '../admin/cloudflare_core_pages_test.dart' show pumpCore;

const packageName = 'collect_license_offline_fixture';
const notice =
    'Exact offline notice.\n\nKeep this attribution with the software.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    LicenseRegistry.reset();
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([packageName], notice);
    });
  });
  tearDownAll(LicenseRegistry.reset);

  testWidgets(
    'mobile settings opens complete offline notices at enlarged text and returns',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FixtureCollectRepository();
      final router = createAppRouter(initialLocation: '/settings');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text('Open-source licenses');
      await tester.scrollUntilVisible(
        entry.hitTestable(),
        160,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/settings/legal/licenses',
      );
      expect(find.byType(CollectLicensesPage), findsOneWidget);
      await tester.tap(
        find
            .ancestor(
              of: find.text(packageName),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Exact offline notice.'), findsOneWidget);
      expect(
        find.text('Keep this attribution with the software.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cookie Admin exposes notices without an operating-data request and keeps session admission',
    (tester) async {
      final unexpectedRequests = <String>[];
      final container = await pumpCore(tester, (request) async {
        unexpectedRequests.add(request.url.path);
        throw StateError('No operating transport is needed for licenses.');
      }, permissions: ['overview.read', 'account.manage']);
      final router = container.read(cloudflareAdminRouterProvider);
      router.go('/admin/security');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open-source licenses'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/licenses');
      expect(find.byType(CloudflareAdminLicensesPage), findsOneWidget);
      await tester.tap(find.byTooltip('Open $packageName'));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      expect(unexpectedRequests, isEmpty);
      expect(tester.takeException(), isNull);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/login');
      expect(find.byType(CloudflareAdminLicensesPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
