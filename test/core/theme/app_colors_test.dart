// ignore_for_file: deprecated_member_use_from_same_package
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
      Color(0xFFF7F8F6),
      Color(0xFFE7EBE7),
    ]);
    expect(AppColors.blueGradient.colors, const <Color>[
      Color(0xFFF5F7FA),
      Color(0xFFE8EEF3),
    ]);

    AppColors.applyBrightness(Brightness.dark);
    expect(AppColors.cardGradient.colors, const <Color>[
      Color(0xFF353836),
      Color(0xFF2E312F),
    ]);
    expect(AppColors.blueGradient.colors, const <Color>[
      Color(0xFF141B1C),
      Color(0xFF1A2527),
    ]);
  });
}
