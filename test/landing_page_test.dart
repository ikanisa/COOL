import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Collect landing page explains the full business model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CollectLandingPage()));
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
      find.text('*182*8*1*41258*2000#'),
      600,
      scrollable: verticalScrollable,
    );
    expect(find.text('*182*8*1*41258*2000#'), findsOneWidget);
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
      '/impact',
      '/our-partners',
      '/privacy',
      '/account-deletion',
      '/data-deletion',
      '/terms',
    ]) {
      final page = publicPageForPath(path);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(path),
          home: CollectPublicPage(data: page),
        ),
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
      MaterialApp(home: CollectPublicPage(data: publicPageForPath('/privacy'))),
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

    await tester.pumpWidget(const MaterialApp(home: CollectLandingPage()));

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
      MaterialApp(
        home: CollectPublicPage(data: publicPageForPath('/group-savings')),
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
        MaterialApp(
          key: ValueKey('copy-$path'),
          home: CollectPublicPage(data: publicPageForPath(path)),
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
        'payment intent',
        'raw sms',
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
        'ussd',
      ]) {
        expect(
          visibleText,
          isNot(contains(banned)),
          reason: '$path should not expose "$banned"',
        );
      }
    }
  });

  testWidgets(
    'Impact and partners pages present public data without projections',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final path in const ['/impact', '/our-partners']) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('numbers-$path'),
            home: CollectPublicPage(data: publicPageForPath(path)),
          ),
        );

        final visibleText = find
            .byType(Text)
            .evaluate()
            .map((element) => (element.widget as Text).data ?? '')
            .join(' ');

        final requiredNumbers = switch (path) {
          '/impact' => const [
            '864M',
            'RWF 19,807B',
            '7,169,324',
            '169,570',
            '~60%',
            'RWF 351.3B',
            'RWF 67.6B',
            '26.2%',
            '25,000',
            '70,000',
          ],
          '/our-partners' => const [
            '864M',
            'RWF 19,807B',
            '7,169,324',
            '169,570',
            '~60%',
            'RWF 351.3B',
            'RWF 67.6B',
            '26.2%',
            '25,000',
            '70,000',
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
    },
  );
}
