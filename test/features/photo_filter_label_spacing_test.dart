import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_group_photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });
  testWidgets('3.2x photo filter labels clear preceding controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(3.2)),
          child: Scaffold(body: CollectGroupPhotoSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All photos'));
    await tester.pumpAndSettle();
    final chip = find.ancestor(
      of: find.text('All photos'),
      matching: find.byType(ChoiceChip),
    );
    expect(
      tester.getRect(find.text('Theme')).top - tester.getRect(chip).bottom,
      greaterThanOrEqualTo(8),
      reason: 'The floating label must clear the preceding photo mode chip',
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Occasion'));
    await tester.pumpAndSettle();
    final theme = find.byType(DropdownButtonFormField<String>).first;
    expect(
      tester.getRect(find.text('Occasion')).top - tester.getRect(theme).bottom,
      greaterThanOrEqualTo(8),
      reason: 'The second label must clear the previous field border',
    );
    expect(tester.takeException(), isNull);
  });
}
