import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark mode surfaces have strong visual separation', () {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();
    final light = lightTheme.extension<CollectColors>()!;
    final dark = darkTheme.extension<CollectColors>()!;

    expect(lightTheme.brightness, Brightness.light);
    expect(darkTheme.brightness, Brightness.dark);

    expect(
      light.surfaceReadable.computeLuminance() -
          dark.surfaceReadable.computeLuminance(),
      greaterThan(0.85),
    );
    expect(
      light.surfaceMuted.computeLuminance() -
          dark.surfaceMuted.computeLuminance(),
      greaterThan(0.65),
    );
    expect(
      light.textPrimary.computeLuminance() -
          dark.textPrimary.computeLuminance(),
      lessThan(-0.70),
    );
    expect(
      light.panelSurface.computeLuminance() -
          dark.panelSurface.computeLuminance(),
      greaterThan(0.80),
    );
    expect(
      light.controlSurface.computeLuminance() -
          dark.controlSurface.computeLuminance(),
      greaterThan(0.75),
    );
    expect(
      light.borderAccent.computeLuminance() -
          dark.borderAccent.computeLuminance(),
      greaterThan(0.20),
    );
  });

  test('customer background is solid and adaptive across modes', () {
    final light = AppTheme.light().extension<CollectColors>()!;
    final dark = AppTheme.dark().extension<CollectColors>()!;

    expect(light.screenBase, light.canvas);
    expect(dark.screenBase, dark.canvas);
    expect(light.canvas, isNot(dark.canvas));
  });
}
