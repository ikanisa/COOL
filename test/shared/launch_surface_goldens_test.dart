import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/shared/widgets/cool_async_view.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:cool_app/shared/widgets/cool_error_view.dart';
import 'package:cool_app/shared/widgets/cool_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/google_fonts_test_assets.dart';

void main() {
  const captureKey = Key('launch-surface-capture');
  const phoneSize = Size(390, 844);

  Future<void> settleGoldenApp(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames * 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  }

  Future<void> pumpGolden(WidgetTester tester, {required Widget child}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phoneSize;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: phoneSize,
              devicePixelRatio: 1,
              disableAnimations: true,
            ),
            child: TickerMode(
              enabled: false,
              child: RepaintBoundary(key: captureKey, child: child),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await settleGoldenApp(tester, frames: 8);
  }

  Future<void> expectGolden(WidgetTester tester, String name) {
    return expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/launch_surface/$name.png'),
    );
  }

  setUpAll(setUpBundledGoogleFonts);
  tearDownAll(tearDownBundledGoogleFonts);

  group('CoolButton', () {
    testWidgets('primary icon action', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: CoolButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onTap: null,
                isDisabled: true,
              ),
            ),
          ),
        ),
      );

      await expectGolden(tester, 'cool_button_primary_icon_disabled');
    });

    testWidgets('loading state', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: CoolButton(label: 'Saving', isLoading: true),
            ),
          ),
        ),
      );

      await expectGolden(tester, 'cool_button_loading');
    });
  });

  group('CoolTextField', () {
    testWidgets('labeled input with prefix icon', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: CoolTextField(
              label: 'MoMo Number',
              hint: 'Enter your number',
              prefixIcon: Icons.phone_android_rounded,
            ),
          ),
        ),
      );

      await expectGolden(tester, 'cool_text_field_labeled_phone');
    });
  });

  group('CoolAsyncView', () {
    testWidgets('loading state', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: CoolAsyncView<String>(
            value: const AsyncValue<String>.loading(),
            builder: (data) => Text(data),
          ),
        ),
      );

      await expectGolden(tester, 'cool_async_view_loading');
    });

    testWidgets('error state', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: CoolAsyncView<String>(
            value: AsyncValue<String>.error(
              Exception('Request timed out'),
              StackTrace.empty,
            ),
            builder: (data) => Text(data),
            onRetry: () {},
          ),
        ),
      );

      await expectGolden(tester, 'cool_async_view_error');
    });
  });

  group('CoolErrorView', () {
    testWidgets('retry action state', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: CoolErrorView(
            message: 'Payment intent creation failed.',
            onRetry: () {},
          ),
        ),
      );

      await expectGolden(tester, 'cool_error_view_retry');
    });
  });
}
