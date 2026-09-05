import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('country selection works through its accessibility action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      Country? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showCollectCountryPicker(context);
                },
                child: const Text('Choose country'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose country'));
      await tester.pumpAndSettle();
      final search = find.semantics.byFlag(SemanticsFlag.isTextField);
      expect(search, findsOne);
      expect(
        search.evaluate().single.getSemanticsData().tooltip,
        'Search country',
      );
      tester.semantics.setText(search, 'Rwanda');
      await tester.pumpAndSettle();
      final country = tester.getSemantics(
        find.bySemanticsLabel('Rwanda, calling code +250'),
      );
      expect(country.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        country.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(selected?.countryCode, 'RW');
      expect(find.byType(AuthCountryPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
