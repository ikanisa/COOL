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
      light.glassPanel.computeLuminance() - dark.glassPanel.computeLuminance(),
      greaterThan(0.80),
    );
    expect(
      light.glassControl.computeLuminance() -
          dark.glassControl.computeLuminance(),
      greaterThan(0.75),
    );
    expect(
      light.borderAccent.computeLuminance() -
          dark.borderAccent.computeLuminance(),
      greaterThan(0.20),
    );
  });

  test('route background families stay stable across light and dark modes', () {
    final light = AppTheme.light().extension<CollectColors>()!;
    final dark = AppTheme.dark().extension<CollectColors>()!;

    for (final route in const [
      '/home',
      '/groups',
      '/groups/create',
      '/groups/col-church/contribute',
      '/groups/col-church/share',
      '/settings/help',
      '/offline',
    ]) {
      expect(
        _gradientColors(light.screenGradientForPath(route)),
        _gradientColors(dark.screenGradientForPath(route)),
        reason:
            'Light/dark mode changes surfaces and text, not the reference route background for $route.',
      );
    }
  });
}

List<Color> _gradientColors(Gradient gradient) {
  return switch (gradient) {
    LinearGradient(:final colors) => colors,
    RadialGradient(:final colors) => colors,
    SweepGradient(:final colors) => colors,
    _ => throw StateError('Unsupported gradient type: $gradient'),
  };
}
