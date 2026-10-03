import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
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
  testWidgets('enlarged confirmation labels stay inside their pill and act', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? decision;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3.2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                decision = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      const AuthPhoneConfirmationSheet(phone: '+250788123456'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final label in ['Confirm and send', 'Edit number']) {
      final text = find.text(label);
      await tester.ensureVisible(text);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      final button = find.ancestor(
        of: text,
        matching: find.byType(FilledButton),
      );
      final bounds = tester.getRect(button);
      final path = const StadiumBorder().getOuterPath(bounds);
      final lines = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      );
      for (final line in lines) {
        final ink = line
            .toRect()
            .deflate(3)
            .shift(paragraph.localToGlobal(Offset.zero));
        expect(
          [
            ink.topLeft,
            ink.topRight,
            ink.bottomLeft,
            ink.bottomRight,
          ].every(path.contains),
          isTrue,
          reason: '$label must remain inside its painted pill',
        );
      }
    }
    await tester.tap(find.text('Edit number'));
    await tester.pumpAndSettle();
    expect(decision, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm and send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and send'));
    await tester.pumpAndSettle();
    expect(decision, isTrue);
    expect(tester.takeException(), isNull);
  });
}
