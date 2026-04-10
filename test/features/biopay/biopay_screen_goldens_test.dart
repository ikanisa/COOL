import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_home_screen.dart';
import 'package:cool_app/features/biopay/screens/biopay_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/google_fonts_test_assets.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  const captureKey = Key('biopay-golden-capture');
  const phoneSize = Size(390, 844);

  Future<void> settleGoldenApp(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames * 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  }

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Widget child,
    ProviderContainer? container,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phoneSize;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final app = MaterialApp(
      theme: AppTheme.dark,
      builder: (context, widget) => MediaQuery(
        data: const MediaQueryData(
          size: phoneSize,
          devicePixelRatio: 1,
          disableAnimations: true,
        ),
        child: widget!,
      ),
      home: RepaintBoundary(key: captureKey, child: child),
    );

    await tester.pumpWidget(
      container == null
          ? ProviderScope(child: app)
          : UncontrolledProviderScope(container: container, child: app),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await settleGoldenApp(tester, frames: 8);
  }

  Future<void> expectGolden(WidgetTester tester, String name) {
    return expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  setUpAll(setUpBundledGoogleFonts);
  tearDownAll(tearDownBundledGoogleFonts);

  testWidgets('home screen', (tester) async {
    await pumpGolden(tester, child: const BiopayHomeScreen());
    await expectGolden(tester, 'biopay_home_screen');
  });

  testWidgets('register screen with model issue', (tester) async {
    final container = createTestContainer(
      overrides: [
        biopayModelAssetIssueProvider.overrideWith(
          (ref) async => 'BioPay face model is not bundled in this build yet.',
        ),
        biopayProfileProvider.overrideWith((ref) async => null),
      ],
    );

    await pumpGolden(
      tester,
      container: container,
      child: const BiopayRegisterScreen(),
    );
    await expectGolden(tester, 'biopay_register_screen_model_issue');
  });
}
