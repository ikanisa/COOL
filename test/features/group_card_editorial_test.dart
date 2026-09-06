import 'dart:convert';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/collect_repository_fixture.dart';

void main() {
  final fixture = FixtureCollectRepository().state.collections.first;
  const longTitle =
      'Abanyamuryango ba Kigali saving together for our shared future';
  final totals = CollectionSummary.multiCurrency(
    totals: const {'RWF': 12345678, 'EUR': 250099, 'USD': 81234},
    ownBalances: const {},
    supporterCount: null,
  );

  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    CollectCollection? collection,
    CollectionSummary? summary,
    GroupCardVariant variant = GroupCardVariant.publicDiscovery,
    double scale = 1,
    Brightness brightness = Brightness.dark,
    VoidCallback? open,
    VoidCallback? contribute,
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 740),
            textScaler: TextScaler.linear(scale),
            highContrast: scale == 2,
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: GroupCard(
                collection: collection ?? fixture,
                summary:
                    summary ??
                    const CollectionSummary(
                      amountRaisedRwf: 35000,
                      supporterCount: 3,
                    ),
                variant: variant,
                onTap: open,
                primaryAction: GroupCardActionButton(
                  tooltip: 'Contribute to this group',
                  onPressed: contribute,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final variant in GroupCardVariant.values) {
      testWidgets(
        '$variant preserves long names and all currencies in $brightness at 200%',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await pumpCard(
              tester,
              collection: fixture.copyWith(title: longTitle),
              summary: totals,
              variant: variant,
              scale: 2,
              brightness: brightness,
            );
            final card = tester.getRect(find.byType(GroupCard));
            final title = tester.renderObject<RenderParagraph>(
              find.text(longTitle),
            );
            expect(title.didExceedMaxLines, isFalse);
            expect(
              tester.getRect(find.text(longTitle)).width,
              lessThan(card.width),
            );
            expect(card.height, greaterThan(card.width));
            final amount = find.textContaining('EUR');
            expect(amount, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(amount);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.text.toPlainText(), contains('RWF'));
            expect(paragraph.text.toPlainText(), contains('USD'));
            expect(find.text('—'), findsOneWidget);
            expect(
              find.bySemanticsLabel(RegExp('Contributor count unavailable')),
              findsWidgets,
            );
            await tester.ensureVisible(
              find.byTooltip('Contribute to this group'),
            );
            await tester.pumpAndSettle();
            expect(
              find.byTooltip('Contribute to this group').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'opening a card and contributing remain separate touch and keyboard actions',
    (tester) async {
      var opened = 0;
      var contributions = 0;
      await pumpCard(
        tester,
        open: () => opened++,
        contribute: () => contributions++,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(GroupCard)) + const Offset(120, 120),
      );
      expect(opened, 1);
      expect(contributions, 0);
      await tester.tap(find.byTooltip('Contribute to this group'));
      expect(opened, 1);
      expect(contributions, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(contributions, 2);
      expect(opened, 2);
    },
  );

  testWidgets(
    'uploaded media takes priority and failed media keeps the same card geometry',
    (tester) async {
      final original = fixture.imageUrl;
      final asset = await rootBundle.load(
        'assets/marketing/rwanda/shared-goals.png',
      );
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      await pumpCard(
        tester,
        collection: fixture.copyWith(
          imageUrl: 'data:image/png;base64,${base64Encode(bytes)}',
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image).first).image,
        isA<MemoryImage>(),
      );
      final uploadedRect = tester.getRect(find.byType(GroupCard));
      await pumpCard(
        tester,
        collection: fixture.copyWith(imageUrl: 'data:image/png;base64,%%%'),
      );
      expect(
        tester.widget<Image>(find.byType(Image).first).image,
        isNot(isA<MemoryImage>()),
      );
      expect(tester.getRect(find.byType(GroupCard)), uploadedRect);
      expect(find.text(fixture.title), findsOneWidget);
      expect(find.text('RWF 35,000'), findsOneWidget);
      expect(fixture.imageUrl, original);
      expect(tester.takeException(), isNull);
    },
  );
}
