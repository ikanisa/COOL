import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:collect_app/features/landing/public_marketing_theme.dart';
import 'package:collect_app/main_public.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/collect_repository_fixture.dart';

Widget publicHarness(Widget child, {Key? key, double textScale = 1}) {
  return ProviderScope(
    child: MaterialApp(
      key: key,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    ),
  );
}

String visibleText() => find
    .byType(Text)
    .evaluate()
    .map((element) => (element.widget as Text).data ?? '')
    .join(' ')
    .toLowerCase();

Future<void> _expectRequestReviewContent(
  WidgetTester tester,
  String path,
) async {
  expect(
    tester.widget<CollectPublicPage>(find.byType(CollectPublicPage)).data.path,
    path,
  );
  expect(
    find.textContaining('Settings > Security > Delete data'),
    findsOneWidget,
  );
  for (final statement in [
    'Submitting a request does not delete your account',
    'receipt records your request for review',
    path == '/data-deletion'
        ? 'in-app account-deletion request status'
        : 'request status in the app',
  ]) {
    final content = find.textContaining(statement);
    expect(content, findsOneWidget);
    await tester.ensureVisible(content);
    await tester.pumpAndSettle();
    expect(content.hitTestable(), findsOneWidget);
  }
  expect(find.textContaining('signs out after'), findsNothing);
  expect(
    find.textContaining('explanation of the completed action'),
    findsNothing,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  test('public marketing action distinguishes disabled and focused states', () {
    final theme = CollectPublicMarketingTheme.light();
    final style = theme.filledButtonTheme.style!;
    expect(theme.brightness, Brightness.light);
    final resting = style.backgroundColor!.resolve({});
    final disabled = style.backgroundColor!.resolve({WidgetState.disabled});
    expect(resting, CollectPublicMarketingTheme.action);
    expect(disabled, isNot(resting));
    expect(
      style.foregroundColor!.resolve({WidgetState.disabled}),
      isNot(style.foregroundColor!.resolve({})),
    );
    expect(style.side!.resolve({WidgetState.focused})!.width, 2);
    final foreground = style.foregroundColor!.resolve({WidgetState.disabled})!;
    final contrast =
        (disabled!.computeLuminance() + .05) /
        (foreground.computeLuminance() + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });

  testWidgets('landing page presents Rwanda MoMo USSD', (tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(publicHarness(const CollectLandingPage()));

    expect(
      find.text('Rwanda MoMo contributions, clearly recorded.'),
      findsOneWidget,
    );
    expect(find.text('Get the App'), findsWidgets);
    expect(find.text('How groups work'), findsOneWidget);
    // Public content is now an editorial sequence below the photographic
    // hero. Validate the real task content after scrolling to its section.
    await tester.scrollUntilVisible(
      find.text('One clear contribution journey'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('One clear contribution journey'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Standalone and privacy-first'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Standalone and privacy-first'), findsOneWidget);
    expect(find.text('Verified MoMo receiver'), findsOneWidget);
    expect(find.text('Controlled evidence'), findsOneWidget);
    expect(find.text('Daily reconciliation'), findsOneWidget);
    expect(find.text('Balanced ledger'), findsOneWidget);

    final text = visibleText();
    for (final removed in const [
      'credit-readiness',
      'insurance',
      'insurer',
      'lending',
      'loan',
      'stripe',
      'collateral',
    ]) {
      expect(text, isNot(contains(removed)));
    }
  });

  testWidgets('homepage explainer action opens the group journey page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CollectLandingPage()),
        GoRoute(
          path: '/group-savings',
          builder: (_, _) =>
              CollectPublicPage(data: publicPageForPath('/group-savings')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('How groups work'));
    await tester.pumpAndSettle();
    expect(
      find.text('Rwanda MoMo contributions in one clear ledger.'),
      findsOneWidget,
    );
    expect(find.text('Create Group'), findsNothing);
  });

  testWidgets('shipping public routes explain review to anonymous visitors', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        collectRepositoryProvider.overrideWith(
          (ref) => FixtureCollectRepository(seeded: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectPublicWebsiteApp(),
      ),
    );
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final router = app.routerConfig! as GoRouter;
    addTearDown(router.dispose);
    expect(container.read(collectAuthenticatedUserIdProvider), isNull);

    for (final path in ['/account-deletion', '/data-deletion']) {
      router.go('$path/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, path);
      await _expectRequestReviewContent(tester, path);
      await tester.tap(find.byTooltip('Collect home'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(CollectLandingPage), findsOneWidget);
      expect(container.read(collectAuthenticatedUserIdProvider), isNull);
    }
  });

  testWidgets('anonymous Admin routes preserve the public-build access guard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        collectRepositoryProvider.overrideWith(
          (ref) => FixtureCollectRepository(seeded: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    final mountedRouters = <GoRouter>{};
    GoRouter mountedRouter() {
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final router = app.routerConfig! as GoRouter;
      mountedRouters.add(router);
      return router;
    }

    addTearDown(() {
      for (final router in mountedRouters) {
        router.dispose();
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(adminAuthSessionScopeProvider), isNull);
    expect(container.read(adminAuthGuardProvider).isAuthorized, isFalse);
    final supportsPublicPages =
        publicLandingHome &&
        Uri.base.host.toLowerCase() != 'admin.collect.ikanisa.com';

    for (final path in ['/account-deletion', '/data-deletion']) {
      mountedRouter().go(path);
      await tester.pumpAndSettle();
      final router = mountedRouter();
      expect(router, same(container.read(adminRouterProvider)));
      if (supportsPublicPages) {
        expect(router.routerDelegate.currentConfiguration.uri.path, path);
        await _expectRequestReviewContent(tester, path);
        await tester.tap(find.byTooltip('Collect home'));
        await tester.pumpAndSettle();
        expect(
          mountedRouter().routerDelegate.currentConfiguration.uri.path,
          '/',
        );
        expect(find.byType(CollectLandingPage), findsOneWidget);
      } else {
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/admin/login',
        );
        expect(find.byType(AdminLoginPage), findsOneWidget);
        expect(find.byType(CollectPublicPage), findsNothing);
      }
      expect(find.byType(AdminShell), findsNothing);
      expect(container.read(adminAuthSessionScopeProvider), isNull);
      expect(container.read(adminAuthGuardProvider).isAuthorized, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  test('public route inventory excludes removed financial-expansion pages', () {
    expect(publicWebsitePaths, {
      '/',
      '/group-savings',
      '/community-groups',
      '/trust',
      '/security',
      '/privacy',
      '/account-deletion',
      '/data-deletion',
      '/terms',
    });
    for (final removed in const [
      '/diaspora',
      '/insurance',
      '/craas',
      '/our-partners',
      '/credit-readiness',
    ]) {
      expect(publicWebsitePaths, isNot(contains(removed)));
    }
  });

  testWidgets('all standalone public pages render their customer content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final path in publicWebsitePaths.where((path) => path != '/')) {
      final page = publicPageForPath(path);
      await tester.pumpWidget(
        publicHarness(CollectPublicPage(data: page), key: ValueKey(path)),
      );
      expect(find.text(page.title), findsOneWidget);
      expect(find.text(page.sections.first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('privacy page covers payment evidence and deletion controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      publicHarness(CollectPublicPage(data: publicPageForPath('/privacy'))),
    );

    expect(find.text('Privacy Policy and Data Deletion'), findsOneWidget);
    expect(find.text('How payment evidence is handled'), findsOneWidget);
    expect(find.text('Account deletion request'), findsOneWidget);
    expect(find.text('Data deletion and correction request'), findsOneWidget);
    expect(find.textContaining('info@ikanisa.com'), findsWidgets);
    expect(find.textContaining('+250 795 588 248'), findsWidgets);
    expect(
      find.textContaining('Matched MoMo receipt evidence determines'),
      findsOneWidget,
    );
    expect(find.textContaining('OpenAI'), findsNothing);
  });

  testWidgets('home navigation stays visible and readable beyond the photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(publicHarness(const CollectLandingPage()));
    await tester.pumpAndSettle();
    final navigation = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'How it works',
    );
    final initialPosition = tester.getCenter(navigation);
    final initialColor = tester.widget<IconButton>(navigation).color;

    await tester.scrollUntilVisible(
      find.text('One clear contribution journey'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(navigation), initialPosition);
    expect(tester.widget<IconButton>(navigation).color, isNot(initialColor));
    expect(tester.takeException(), isNull);
  });

  testWidgets('public pages remain usable at 320 px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      publicHarness(const CollectLandingPage(), textScale: 2),
    );
    await tester.pump();
    expect(find.text('Collect'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final path in publicWebsitePaths.where((path) => path != '/')) {
      final data = publicPageForPath(path);
      await tester.pumpWidget(
        publicHarness(
          CollectPublicPage(data: data),
          key: ValueKey('compact-$path'),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(find.text(data.title), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Compact public $path');
    }
  });
}
