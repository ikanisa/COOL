import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('keyboard-surface-capture');
const _cardKey = ValueKey('keyboard-card');
const _rowKey = ValueKey('keyboard-row');

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final entry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
    'high-contrast-light': AppTheme.highContrastLight(),
    'high-contrast-dark': AppTheme.highContrastDark(),
  }.entries) {
    testWidgets('${entry.key} keyboard focus moves from card to nested row', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      });
      var cardActivated = 0;
      var rowActivated = 0;
      var finalActivated = 0;
      await _pump(
        tester,
        entry.value,
        cardAction: () => cardActivated++,
        rowAction: () => rowActivated++,
        finalAction: () => finalActivated++,
      );
      final card = find.byKey(_cardKey);
      final row = find.byKey(_rowKey);
      final cardInk = find
          .descendant(of: card, matching: find.byType(InkWell))
          .first;
      final rowInk = find.descendant(of: row, matching: find.byType(InkWell));
      final cardPaint = _surfacePaint(card).first;
      final rowPaint = _surfacePaint(row);
      final restingCardRect = tester.getRect(card);
      final restingRowRect = tester.getRect(row);
      final tokens = entry.value.extension<CollectUniversalTokens>()!;
      final resting = await _capture(tester, '${entry.key}-resting');
      final cardRingPoint =
          tester.getRect(cardPaint).topCenter +
          Offset(0, tokens.focusRingWidth * 1.5);

      await _tab(tester);
      expect(
        tester.widget<InkWell>(cardInk).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      expect(
        tester.widget<CustomPaint>(cardPaint).foregroundPainter,
        isNotNull,
      );
      expect(tester.widget<CustomPaint>(rowPaint).foregroundPainter, isNull);
      final focused = await _capture(tester, '${entry.key}-card-focused');
      expect(focused.colourAt(cardRingPoint), tokens.focusRing);
      expect(resting.colourAt(cardRingPoint), isNot(tokens.focusRing));
      // The inset focus line remains distinct from a permanent contrast border.
      final gap = focused.colourAt(
        tester.getRect(cardPaint).topCenter +
            Offset(0, tokens.focusRingWidth / 2),
      );
      expect(_contrast(tokens.focusRing, gap), greaterThanOrEqualTo(3));
      expect(tester.getRect(card), restingCardRect);
      expect(tester.getRect(row), restingRowRect);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cardActivated, 1);
      expect(rowActivated, 0);

      await _tab(tester);
      expect(tester.widget<InkWell>(rowInk).focusNode!.hasPrimaryFocus, isTrue);
      expect(tester.widget<CustomPaint>(cardPaint).foregroundPainter, isNull);
      expect(tester.widget<CustomPaint>(rowPaint).foregroundPainter, isNotNull);
      final focusedRow = await _capture(tester, '${entry.key}-row-focused');
      final rowRingPoint =
          tester.getRect(rowPaint).topCenter -
          Offset(0, tokens.focusRingWidth / 2);
      expect(focusedRow.colourAt(rowRingPoint), tokens.focusRing);
      expect(resting.colourAt(rowRingPoint), isNot(tokens.focusRing));
      expect(
        _contrast(
          tokens.focusRing,
          focusedRow.colourAt(
            tester.getRect(rowPaint).topCenter +
                Offset(0, tokens.focusRingWidth * 2),
          ),
        ),
        greaterThanOrEqualTo(3),
      );
      expect(tester.getRect(card), restingCardRect);
      expect(tester.getRect(row), restingRowRect);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(rowActivated, 1);
      expect(cardActivated, 1);

      // Read-only cards and rows introduce no tab stops; the next activation
      // must reach the following action directly.
      await _tab(tester);
      expect(tester.widget<CustomPaint>(rowPaint).foregroundPainter, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(finalActivated, 1);
      expect(cardActivated, 1);
      expect(rowActivated, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('touch focus keeps the resting surface until keyboard input', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
    var activated = 0;
    await _pump(
      tester,
      AppTheme.dark(),
      cardAction: () => activated++,
      rowAction: () {},
      finalAction: () {},
    );
    final card = find.byKey(_cardKey);
    final ink = find.descendant(of: card, matching: find.byType(InkWell)).first;
    final paint = _surfacePaint(card).first;
    tester.widget<InkWell>(ink).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.widget<InkWell>(ink).focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.widget<CustomPaint>(paint).foregroundPainter, isNull);
    await tester.tap(find.text('Open group summary'));
    await tester.pumpAndSettle();
    expect(activated, 1);
    expect(tester.widget<CustomPaint>(paint).foregroundPainter, isNull);

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpAndSettle();
    expect(tester.widget<CustomPaint>(paint).foregroundPainter, isNotNull);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pumpAndSettle();
    expect(tester.widget<CustomPaint>(paint).foregroundPainter, isNull);
    expect(tester.takeException(), isNull);
  });
}

Finder _surfacePaint(Finder surface) => find.descendant(
  of: surface,
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.child is InkWell,
  ),
);

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  required VoidCallback cardAction,
  required VoidCallback rowAction,
  required VoidCallback finalAction,
}) async {
  tester.view.physicalSize = const Size(480, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(
        key: _captureKey,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CollectCard(child: Text('Confirmed group summary')),
                const SizedBox(height: 16),
                CollectCard(
                  key: _cardKey,
                  onTap: cardAction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Open group summary'),
                      const SizedBox(height: 16),
                      CollectListTile(
                        key: _rowKey,
                        title: 'View members',
                        subtitle: 'Review roles in this group',
                        onTap: rowAction,
                      ),
                    ],
                  ),
                ),
                const CollectListTile(title: 'Confirmed contribution count'),
                CollectButton(label: 'Continue', onPressed: finalAction),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<_Pixels> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final directory = Platform.environment['COLLECT_SURFACE_FOCUS_CAPTURE_DIR'];
    if (directory != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File('$directory/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
    final pixels = _Pixels(rgba!.buffer.asUint8List(), image.width);
    image.dispose();
    return pixels;
  });
  return result!;
}

class _Pixels {
  _Pixels(this.bytes, this.width);

  final Uint8List bytes;
  final int width;

  Color colourAt(Offset point) {
    final index = (point.dy.floor() * width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes[index + 3],
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
    );
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return ((first > second ? first : second) + 0.05) /
      ((first > second ? second : first) + 0.05);
}
