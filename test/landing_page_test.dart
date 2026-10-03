import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:collect_app/features/landing/public_marketing_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
