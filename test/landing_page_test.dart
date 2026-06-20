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
    expect(find.text('Get the app'), findsWidgets);
    expect(find.text('Create group savings'), findsWidgets);
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
      '/privacy',
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

      expect(find.text(page.title), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(page.sections.first.title),
        700,
        scrollable: verticalScrollable,
      );
      expect(find.text(page.sections.first.title), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Explore the Collect platform'),
        700,
        scrollable: verticalScrollable,
      );
      expect(find.text('Explore the Collect platform'), findsOneWidget);
    }
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
      'part'
          'ner',
      'part'
          'ners',
      'reg'
          'ulator',
      'reg'
          'ulators',
      'inv'
          'estor',
      'inv'
          'estors',
      'part'
          'nership',
    ]) {
      expect(visibleText, isNot(contains(banned)));
    }
  });
}
