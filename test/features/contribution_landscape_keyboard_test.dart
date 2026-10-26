import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('RWF entry survives landscape keyboard at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FixtureCollectRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ContributionFlowScreen(
              collectionId: 'qa-private-group',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = find.byType(TextField);
      await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(field.hitTestable(), findsOneWidget);
      await tester.enterText(field, '1234');
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FilledButton, 'Continue to MoMo');
      if (action.evaluate().isEmpty) {
        final scrollable = Scrollable.of(tester.element(field));
        await tester.scrollUntilVisible(
          action,
          80,
          scrollable: find.byWidget(scrollable.widget),
          maxScrolls: 30,
        );
      }
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
