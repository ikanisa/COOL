import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('landing page presents Rwanda MoMo and diaspora bank rails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(publicHarness(const CollectLandingPage()));

    expect(
      find.text('MoMo at home. Bank transfer in the diaspora.'),
      findsOneWidget,
    );
    expect(find.text('Get the App'), findsWidgets);
    expect(find.text('Create Group'), findsOneWidget);
    expect(find.text('One clear contribution journey'), findsOneWidget);
    expect(find.text('Standalone and privacy-first'), findsOneWidget);
    expect(find.text('Approved beneficiary'), findsOneWidget);
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
      find.textContaining('Diaspora daily statements determine'),
      findsOneWidget,
    );
    expect(find.textContaining('OpenAI'), findsNothing);
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

    await tester.pumpWidget(
      publicHarness(
        CollectPublicPage(data: publicPageForPath('/privacy')),
        key: const ValueKey('privacy-compact'),
        textScale: 2,
      ),
    );
    await tester.pump();
    expect(find.text('Privacy Policy and Data Deletion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
