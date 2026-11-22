import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  for (final scale in [1.0, 3.2]) {
    testWidgets('320px ${scale}x hero actions preserve words and activation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      const labels = ['Contribute & Join', 'Members', 'Share', 'Manage'];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: CollectHeroQuickActionRow(
                  actions: [
                    for (final label in labels)
                      CollectHeroQuickAction(
                        icon: Icons.group_outlined,
                        label: label,
                        onTap: () => taps++,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in labels) {
        final text = find.text(label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        var offset = 0;
        for (final word in label.split(' ')) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: offset,
              extentOffset: offset + word.length,
            ),
          );
          expect(boxes, isNotEmpty, reason: word);
          expect(
            boxes.every((box) => (box.top - boxes.first.top).abs() < 0.01),
            isTrue,
            reason: '$word must remain whole at ${scale}x',
          );
          offset += word.length + 1;
        }
        await tester.ensureVisible(text);
        await tester.tap(text);
      }
      expect(taps, labels.length);
      expect(tester.takeException(), isNull);
    });
  }
}
