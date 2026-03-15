import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_palette.dart';
import 'package:cool_app/core/theme/theme_system_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AnnotatedRegion<SystemUiOverlayStyle> overlayRegion(WidgetTester tester) {
    return tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
  }

  testWidgets('applies light system chrome for dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const ThemeSystemChrome(child: SizedBox()),
      ),
    );

    final overlay = overlayRegion(tester).value;

    expect(overlay.statusBarIconBrightness, Brightness.light);
    expect(overlay.systemNavigationBarIconBrightness, Brightness.light);
    expect(overlay.systemNavigationBarColor, CoolPalette.dark.surface);
  });

  testWidgets('applies dark system chrome for light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ThemeSystemChrome(child: SizedBox()),
      ),
    );

    final overlay = overlayRegion(tester).value;

    expect(overlay.statusBarIconBrightness, Brightness.dark);
    expect(overlay.systemNavigationBarIconBrightness, Brightness.dark);
    expect(overlay.systemNavigationBarColor, CoolPalette.light.surface);
  });
}
