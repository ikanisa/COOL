import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/features/auth/widgets/collect_google_sign_in_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _buttonKey = ValueKey('google_sign_in_test_button');

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  testWidgets('Google action supports touch and keyboard activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var activations = 0;
      await _pumpButton(tester, onPressed: () => activations++);
      await tester.pumpAndSettle();

      final button = find.byType(OutlinedButton);
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.label, 'Continue with Google');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(activations, 1);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(button)
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        ui.Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activations, 3);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final busy in [false, true]) {
    testWidgets(
      '${busy ? 'busy' : 'disabled'} Google action does not activate',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var activations = 0;
          await _pumpButton(
            tester,
            onPressed: busy ? () => activations++ : null,
            busy: busy,
          );
          final button = find.byType(OutlinedButton);
          final data = tester.getSemantics(button).getSemanticsData();
          expect(
            data.label,
            busy ? 'Connecting to Google' : 'Continue with Google',
          );
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
          expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
          if (busy) expect(data.flagsCollection.isLiveRegion, isTrue);
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          expect(
            find.byType(CircularProgressIndicator),
            busy ? findsOneWidget : findsNothing,
          );

          await tester.tap(button);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump(const Duration(milliseconds: 100));
          expect(activations, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final dark in [false, true]) {
    for (final busy in [false, true]) {
      testWidgets(
        '${dark ? 'dark' : 'light'} Google ${busy ? 'busy' : 'ready'} action grows at 200 percent text',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await _pumpButton(tester, onPressed: () {}, busy: busy, dark: dark);
            final normalSize = tester.getSize(find.byKey(_buttonKey));
            expect(normalSize.width, 288);
            expect(normalSize.height, greaterThanOrEqualTo(48));

            await _pumpButton(
              tester,
              onPressed: () {},
              busy: busy,
              dark: dark,
              textScale: 2,
            );
            final enlargedSize = tester.getSize(find.byKey(_buttonKey));
            expect(enlargedSize.width, normalSize.width);
            expect(enlargedSize.height, greaterThan(normalSize.height));
            final label = busy
                ? 'Connecting to Google'
                : 'Continue with Google';
            final text = find.text(label);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse);
            final labelBounds = tester.getRect(text);
            final buttonBounds = tester.getRect(find.byKey(_buttonKey));
            expect(buttonBounds.contains(labelBounds.topLeft), isTrue);
            expect(buttonBounds.contains(labelBounds.bottomRight), isTrue);
            expect(find.bySemanticsLabel(label), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '${dark ? 'dark' : 'light'} Google logo retains source proportions and colors on white',
      (tester) async {
        await _pumpButton(tester, onPressed: () {}, dark: dark);
        final imageFinder = find.byType(Image);
        final provider = tester.widget<Image>(imageFinder).image;
        await tester.runAsync(() async {
          await precacheImage(provider, tester.element(imageFinder));
        });
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(imageFinder);
        expect(
          (image.image as AssetImage).assetName,
          'assets/auth/google_g.png',
        );
        expect(image.fit, BoxFit.contain);
        expect(image.color, isNull);
        expect(image.colorBlendMode, isNull);
        expect(image.excludeFromSemantics, isTrue);
        expect(
          tester.getSize(imageFinder).aspectRatio,
          closeTo(200 / 204, 0.000001),
        );
        final decoded = tester.renderObject<RenderImage>(imageFinder).image!;
        expect(decoded.width, 200);
        expect(decoded.height, 204);
        final background = tester.widget<DecoratedBox>(
          find
              .ancestor(of: imageFinder, matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          (background.decoration as BoxDecoration).color,
          CollectColors.publicWhite,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpButton(
  WidgetTester tester, {
  required VoidCallback? onPressed,
  bool busy = false,
  bool dark = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 288,
            child: CollectGoogleSignInButton(
              key: _buttonKey,
              onPressed: onPressed,
              busy: busy,
            ),
          ),
        ),
      ),
    ),
  );
  // Busy indicators animate continuously; these tests use bounded frame pumps.
  await tester.pump(const Duration(milliseconds: 100));
}
