import 'package:cool_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
  });

  test('semantic compatibility colors switch with brightness', () {
    expect(AppColors.bg, AppColors.darkBg);
    expect(AppColors.surface, AppColors.darkSurface);
    expect(AppColors.text, AppColors.darkText);

    AppColors.applyBrightness(Brightness.light);

    expect(AppColors.bg, AppColors.lightBg);
    expect(AppColors.surface, AppColors.lightSurface);
    expect(AppColors.text, AppColors.lightText);
  });

  test('legacy semantic gradients expose light and dark variants', () {
    AppColors.applyBrightness(Brightness.light);
    expect(AppColors.cardGradient.colors, const <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFF0F3FA),
    ]);
    expect(AppColors.blueGradient.colors, const <Color>[
      Color(0xFFF2F7FF),
      Color(0xFFE2ECFF),
    ]);

    AppColors.applyBrightness(Brightness.dark);
    expect(AppColors.cardGradient.colors, const <Color>[
      Color(0xFF151520),
      Color(0xFF1A1A28),
    ]);
    expect(AppColors.blueGradient.colors, const <Color>[
      Color(0xFF0D1B2A),
      Color(0xFF1A2D4A),
    ]);
  });
}
