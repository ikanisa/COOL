import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('shared-native-state-capture');

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name} switch state retains colour and interaction',
      (tester) async {
        var offValue = false;
        var enabledValue = true;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: CollectCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text('Contribution updates'),
                      value: offValue,
                      onChanged: (value) => setState(() => offValue = value),
                    ),
                    SwitchListTile.adaptive(
                      title: const Text('Group reminders'),
                      value: enabledValue,
                      onChanged: (value) =>
                          setState(() => enabledValue = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          theme: AppTheme.dark().copyWith(platform: platform),
        );
        final pixels = await _capture(tester, 'switch-${platform.name}');
        // Verify actual painted controls; the white primary-button palette must
        // not override blue enabled and grey off switch roles (NEX-010).
        expect(
          _countColour(pixels, CollectColors.referenceSwitchBlue),
          greaterThan(20),
        );
        expect(
          _countColour(pixels, CollectColors.referenceSwitchGrey),
          greaterThan(20),
        );
        await tester.tap(find.text('Contribution updates'));
        await tester.pumpAndSettle();
        expect(offValue, isTrue);
        await tester.tap(find.text('Group reminders'));
        await tester.pumpAndSettle();
        expect(enabledValue, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('task segments retain selected meaning at narrow enlarged text', (
    tester,
  ) async {
    var selected = 'All activity';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: PremiumSegmentedFilter<String>(
            values: const ['All activity', 'My contributions'],
            selected: selected,
            labelFor: (value) => value,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
      scale: 2,
      width: 320,
    );
    final pixels = await _capture(tester, 'segments-large-text');
    expect(
      _countColour(pixels, CollectColors.referenceSegmentSelected),
      greaterThan(20),
    );
    await tester.ensureVisible(find.text('My contributions'));
    await tester.tap(find.text('My contributions'));
    await tester.pumpAndSettle();
    expect(selected, 'My contributions');
    expect(
      tester
          .getSemantics(find.text('My contributions'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.2]) {
    testWidgets('error recovery is readable and reachable at 320px ${scale}x', (
      tester,
    ) async {
      var retried = 0;
      const title = 'Your contribution history could not be refreshed';
      const message =
          'Check your connection and try again. Your confirmed contributions are still recorded; this refresh does not submit another contribution.';
      await _pump(
        tester,
        CollectErrorState(
          title: title,
          message: message,
          onRetry: () => retried++,
        ),
        scale: scale,
        width: 320,
        height: 568,
      );
      for (final text in [title, message]) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(text))
              .didExceedMaxLines,
          isFalse,
        );
      }
      await _capture(tester, 'error-320-${scale}x');
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retried, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading and field guidance keep all words at enlarged text', (
    tester,
  ) async {
    const message =
        'Fetching group members and their collection roles. Keep this screen open while the connection recovers.';
    const helper =
        'Enter the full group name so members can recognise the group before contributing.';
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const LoadingStatePanel(
                title: 'Loading group members',
                message: message,
              ),
              const SizedBox(height: 24),
              CollectTextInput(
                controller: controller,
                label: 'Group name',
                helper: helper,
              ),
            ],
          ),
        ),
      ),
      scale: 2,
      width: 320,
    );
    for (final text in [message, helper]) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
        isFalse,
      );
    }
    await _capture(tester, 'loading-and-guidance-large-text');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search preserves its accessible name after input and clearing', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: SearchWithClearField(
            controller: controller,
            label: 'Search group members',
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, '038');
    await tester.pumpAndSettle();
    final namedField = find.semantics.byPredicate((node) {
      final data = node.getSemanticsData();
      return data.label == 'Search group members' && data.value == '038';
    });
    expect(namedField.evaluate(), hasLength(1));
    await _capture(tester, 'search-focused');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast outlines shared cards without a media flag', (
    tester,
  ) async {
    await _pump(
      tester,
      const Padding(
        padding: EdgeInsets.all(16),
        child: CollectCard(child: Text('Confirmed group summary')),
      ),
      theme: AppTheme.highContrastDark(),
    );
    final card = find.byType(CollectCard);
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(of: card, matching: find.byType(AnimatedContainer)),
    );
    final border = (surface.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, CollectColors.dark.focusRing);
    expect(border.top.width, greaterThanOrEqualTo(2));
    await _capture(tester, 'high-contrast-card');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double scale = 1,
  double width = 390,
  double height = 844,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: _captureKey,
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final directory = Platform.environment['COLLECT_NATIVE_STATE_CAPTURE_DIR'];
    if (directory != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File('$directory/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
    image.dispose();
    return rgba!.buffer.asUint8List();
  });
  return result!;
}

int _countColour(Uint8List pixels, Color colour) {
  final rgb = colour.toARGB32();
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] == ((rgb >> 16) & 255) &&
        pixels[i + 1] == ((rgb >> 8) & 255) &&
        pixels[i + 2] == (rgb & 255)) {
      count++;
    }
  }
  return count;
}
