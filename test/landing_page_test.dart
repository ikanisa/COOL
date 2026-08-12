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

void main() {
  testWidgets('Collect landing page explains the full business model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(publicHarness(const CollectLandingPage()));
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    expect(
      find.text("Credit-ready saving for Rwanda's daily economy"),
      findsOneWidget,
    );
    expect(find.text('Get the App'), findsWidgets);
    expect(find.text('Create Group'), findsWidgets);
    expect(find.text('96%'), findsNothing);
    expect(find.text('Adults in ibimina'), findsNothing);
    expect(find.text('Credit-ready records'), findsNothing);
    expect(find.text('Credit-readiness agents'), findsNothing);
    expect(find.text('Three routes into one credit engine'), findsOneWidget);
    expect(
      find.textContaining('diaspora savings into verified ledgers'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('*182**8*1*41258*2000#'),
      600,
      scrollable: verticalScrollable,
    );
    expect(find.text('*182**8*1*41258*2000#'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Built for the missing middle of financial inclusion'),
      600,
      scrollable: verticalScrollable,
    );
    expect(
      find.text('Built for the missing middle of financial inclusion'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Diaspora savings with custody records and collateral rules'),
      600,
      scrollable: verticalScrollable,
    );
    expect(
      find.text('Diaspora savings with custody records and collateral rules'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Embedded insurance for repayment resilience'),
      600,
      scrollable: verticalScrollable,
    );
    expect(
      find.text('Embedded insurance for repayment resilience'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('CRaaS: from loan inquiry to bank-ready file'),
      600,
      scrollable: verticalScrollable,
    );
    expect(
      find.text('CRaaS: from loan inquiry to bank-ready file'),
      findsOneWidget,
    );
  });

  testWidgets('Collect public website pages render as distinct pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final path in const [
      '/group-savings',
      '/diaspora',
      '/insurance',
      '/craas',
      '/community-groups',
      '/our-partners',
      '/trust',
      '/security',
      '/privacy',
      '/account-deletion',
      '/data-deletion',
      '/terms',
    ]) {
      final page = publicPageForPath(path);
      await tester.pumpWidget(
        publicHarness(CollectPublicPage(data: page), key: ValueKey(path)),
      );
      final verticalScrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );

      expect(find.text(page.title), findsWidgets);
      expect(find.text('Get the App'), findsWidgets);
      expect(find.text('Create Group'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text(page.sections.first.title),
        700,
        scrollable: verticalScrollable,
      );
      expect(find.text(page.sections.first.title), findsOneWidget);
      expect(find.text('Explore the Collect platform'), findsNothing);
    }
  });

  testWidgets('Public privacy page covers Play deletion requirements', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      publicHarness(CollectPublicPage(data: publicPageForPath('/privacy'))),
    );

    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    expect(find.text('Privacy Policy and Data Deletion'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Account deletion request'),
      700,
      scrollable: verticalScrollable,
    );
    expect(find.text('Account deletion request'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Data deletion and correction request'),
      700,
      scrollable: verticalScrollable,
    );
    expect(find.text('Data deletion and correction request'), findsOneWidget);
    expect(find.textContaining('info@ikanisa.com'), findsWidgets);
    expect(find.textContaining('+250 795 588 248'), findsWidgets);
    expect(find.textContaining('without reinstalling the app'), findsOneWidget);
  });

  testWidgets('Collect public website avoids internal and non-customer copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(publicHarness(const CollectLandingPage()));

    final visibleText = find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data ?? '')
        .join(' ')
        .toLowerCase();

    for (final banned in const [
      'admin',
      'pi'
          'lot',
      'reg'
          'ulator',
      'reg'
          'ulators',
      'inv'
          'estor',
      'inv'
          'estors',
      'request '
          'deck',
      'looking for '
          'partners',
      'partner '
          'with collect',
    ]) {
      expect(visibleText, isNot(contains(banned)));
    }
  });

  testWidgets('Group savings public page avoids implementation copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      publicHarness(
        CollectPublicPage(data: publicPageForPath('/group-savings')),
      ),
    );

    final visibleText = find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data ?? '')
        .join(' ')
        .toLowerCase();

    for (final banned in const [
      'supabase',
      'parser',
      'parse',
      'payment intent',
      'receiver momo',
      'raw sms',
      'admin operators',
      'backend',
      'android',
      'iphone',
      'realtime',
      'allocation',
      'underwriting',
      'risk flags',
      'mitigants',
      'buri munsi',
      'deck',
    ]) {
      expect(visibleText, isNot(contains(banned)));
    }
  });

  testWidgets('All public website pages avoid internal process copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final path in publicWebsitePaths.where((path) => path != '/')) {
      await tester.pumpWidget(
        publicHarness(
          CollectPublicPage(data: publicPageForPath(path)),
          key: ValueKey('copy-$path'),
        ),
      );

      final visibleText = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .join(' ')
          .toLowerCase();

      final bannedPhrases = <String>[
        'supabase',
        'parser',
        'payment intent',
        'raw sms',
        'backend',
        'iphone',
        'realtime',
        'allocation',
        'underwriting',
        'risk flags',
        'mitigants',
        'buri munsi',
        'deck',
        'service workflow',
        'not a slogan',
        'admin operator',
        'formal credit analysis',
        'ask for app access',
        'start using collect',
        'use momo ussd',
        'open whatsapp and set up',
        'provider handoff',
        'support infrastructure',
        'create group savings',
      ];
      if (path != '/privacy') bannedPhrases.add('android');
      for (final banned in bannedPhrases) {
        expect(
          visibleText,
          isNot(contains(banned)),
          reason: '$path should not expose "$banned"',
        );
      }
    }
  });

  testWidgets('Partners page presents public data without projections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final path in const ['/our-partners']) {
      await tester.pumpWidget(
        publicHarness(
          CollectPublicPage(data: publicPageForPath(path)),
          key: ValueKey('numbers-$path'),
        ),
      );

      final visibleText = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .join(' ');

      final requiredNumbers = switch (path) {
        '/our-partners' => const [
          'RWF 288B+',
          '4.8M',
          'Low-cost deposit mobilisation',
          'Daily-income lending and repayment',
          'Group-backed and diaspora lending',
          'Stronger MSME credit origination',
        ],
        _ => const <String>[],
      };

      for (final required in requiredNumbers) {
        expect(
          visibleText,
          contains(required),
          reason: '$path should keep public-data metric "$required"',
        );
      }

      expect(visibleText.toLowerCase(), isNot(contains('ppt')));
      expect(visibleText.toLowerCase(), isNot(contains('projected')));
      expect(visibleText.toLowerCase(), isNot(contains('projection')));
      expect(visibleText.toLowerCase(), isNot(contains('base case')));
      expect(visibleText.toLowerCase(), isNot(contains('phase 1')));
      expect(visibleText.toLowerCase(), isNot(contains('phase 2')));
    }
  });

  testWidgets('Public detail pages apply the full-site review copy updates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final expectedCopy = <String, List<String>>{
      '/group-savings': [
        'Your group already has trust. Collect adds structure.',
        'Contribute and get proof',
        'Do more with your group savings.',
      ],
      '/diaspora': [
        'Group savings that strengthen access to bank credit.',
        'Diaspora savers face their own barriers to credit.',
        'Use the loan to invest in property or a business in Rwanda',
      ],
      '/insurance': [
        'Protection that fits how people earn.',
        'Income Protection - pays a short-term benefit',
        'Claims decisions stay with the insurer',
      ],
      '/craas': [
        'From loan inquiry to bank-ready file.',
        'Payment access is widespread. Loan preparation support is not.',
        'Financial readiness: accounting, business plan and tax advisory',
      ],
      '/community-groups': [
        'Finance works better when communities lead.',
        'Community and faith: ibimina',
        'Moto-taxi groups - save toward insurance',
      ],
      '/trust': [
        'Security and trust',
        "Collect does not use customers' private financial documents to train publicly available AI models.",
        'Regulatory posture',
      ],
    };

    for (final entry in expectedCopy.entries) {
      final page = publicPageForPath(entry.key);
      final pageText = [
        page.title,
        page.intro,
        for (final section in page.sections) ...[
          section.title,
          section.body,
          ...section.bullets,
        ],
      ].join(' ');

      for (final expected in entry.value) {
        expect(
          pageText,
          contains(expected),
          reason: '${entry.key} should include reviewed copy "$expected"',
        );
      }
      expect(
        pageText,
        isNot(
          contains(
            'Recommended Trust Commitment Subject To Technical Confirmation',
          ),
        ),
      );
    }
  });

  testWidgets('public landing remains usable at 320 px and 200% text', (
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
    expect(find.text('Get the App'), findsWidgets);
    expect(find.text('Create Group'), findsWidgets);
    expect(tester.takeException(), isNull);

    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      find.text('Built for the missing middle of financial inclusion'),
      500,
      scrollable: verticalScrollable,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('public policy page remains usable at 320 px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      publicHarness(
        CollectPublicPage(data: publicPageForPath('/privacy')),
        textScale: 2,
      ),
    );
    await tester.pump();

    expect(find.text('Privacy Policy and Data Deletion'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
