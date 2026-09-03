// Fixture-only follow-up suite. Host must background/foreground the approved
// disposable simulator when the lifecycle-ready marker is emitted.
import 'app_uat_smoke_test.dart' as smoke;
import 'mobile_ios_lifecycle_device_uat_test.dart' as lifecycle;
import 'mobile_performance_device_uat_test.dart' as performance;
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  smoke.main();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scale in [1.0, 2.0]) {
    testWidgets('iOS permissions exclude Android SMS at text scale $scale', (
      tester,
    ) async {
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final router = createAppRouter(initialLocation: '/settings/permissions');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith(
              (ref) => CollectRepository.fixture(),
            ),
            collectThemeModeProvider.overrideWith(
              (ref) => CollectThemeModeController(
                initialMode: ThemeMode.dark,
                loadPersistedMode: false,
              ),
            ),
          ],
          child: const CollectApp(),
        ),
      );
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('App permissions'), findsOneWidget);
      expect(find.text('MoMo receipt SMS'), findsNothing);
      expect(find.text('Review and allow'), findsNothing);
      expect(find.textContaining('on this Android device'), findsNothing);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      final notifications = find.text('Notifications');
      expect(
        tester
            .renderObject<RenderParagraph>(notifications)
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 13),
            ),
        hasLength(1),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('permission_status_Notifications')),
            )
            .dy,
        greaterThan(tester.getBottomLeft(notifications).dy),
      );
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('mobile_native_ios_permissions_$scale');
    });
  }
  testWidgets('large-text native MoMo keeps the entire payee visible', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = createAppRouter(
      initialLocation: '/groups/col-church/contribute',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: ThemeMode.dark,
              loadPersistedMode: false,
            ),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();
    await _dismissKeyboard(tester);
    final amountField = tester.widget<TextField>(find.byType(TextField).first);
    expect(amountField.controller!.text, isEmpty);
    expect(amountField.decoration!.hintText, '0');
    expect(
      tester.renderObject<RenderParagraph>(find.text('0')).didExceedMaxLines,
      isFalse,
    );
    const payee = 'St Michel MTN MoMo';
    await tester.scrollUntilVisible(
      find.text(payee),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(payee)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(payee)).maxLines, isNull);
    expect(
      tester.renderObject<RenderParagraph>(find.text(payee)).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getBottomLeft(find.text(payee)).dy,
      lessThan(
        tester
            .getTopLeft(find.widgetWithText(FilledButton, 'Continue to MoMo'))
            .dy,
      ),
      reason:
          'The complete payee must be above the fixed action, not merely laid out behind it.',
    );
    await binding.takeScreenshot('mobile_native_momo_payee_entry_2.0');
    await tester.enterText(find.byType(TextField).first, '1000');
    await _dismissKeyboard(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(payee),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(payee)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('RWF 1,000'), findsWidgets);
    expect(tester.widget<Text>(find.text(payee)).maxLines, isNull);
    expect(
      tester.renderObject<RenderParagraph>(find.text(payee)).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getBottomLeft(find.text(payee)).dy,
      lessThan(
        tester
            .getTopLeft(find.widgetWithText(FilledButton, 'Open MoMo USSD'))
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('mobile_native_momo_payee_review_2.0');
  });
  performance.main();
  lifecycle.main();
}

Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  for (var frame = 0; frame < 50; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.view.viewInsets.bottom == 0) break;
  }
  expect(
    tester.view.viewInsets.bottom,
    0,
    reason: 'Native keyboard must settle before a full-screen capture.',
  );
  await tester.pumpAndSettle();
}
