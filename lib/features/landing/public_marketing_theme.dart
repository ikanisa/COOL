import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_typography.dart';

/// Runtime adapter for the selected public marketing cohort. This is separate
/// from the native screen families and Business/operator theme.
abstract final class CollectPublicMarketingTheme {
  static const action = Color(0xFF1F1F1F);
  static const widget = Color(0xFFF7F7F7);
  static const border = Color(0xFFE8E8EB);
  static const heroBackdrop = Color(0xFF346EA2);

  static ThemeData light() {
    const ink = CollectColors.publicInk;
    const canvas = CollectColors.publicWhite;
    const secondary = CollectColors.publicSecondary;
    final scheme = const ColorScheme.light().copyWith(
      primary: action,
      onPrimary: canvas,
      secondary: ink,
      onSecondary: canvas,
      surface: canvas,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: widget,
      surfaceContainer: widget,
      surfaceContainerHigh: widget,
      surfaceContainerHighest: border,
      onSurface: ink,
      onSurfaceVariant: secondary,
      outline: border,
      outlineVariant: border,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: CollectTypography.marketingFontFamily,
      scaffoldBackgroundColor: canvas,
      dividerColor: border,
    );
    final text = base.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: CollectTypography.marketingFontFamily,
    );
    const button = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(44, 44)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      ),
      shape: WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: CollectTypography.marketingFontFamily,
          fontSize: 16,
          height: 22 / 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return base.copyWith(
      textTheme: text.copyWith(
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 18, height: 1.5),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 40,
          height: 1.05,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: const IconThemeData(color: ink),
      cardTheme: const CardThemeData(
        color: widget,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: button.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return border;
            if (states.contains(WidgetState.hovered)) {
              return action.withValues(alpha: .85);
            }
            return action;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ? secondary : canvas,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: Color(0xFF234FA6), width: 2)
                : BorderSide.none,
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: button.copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? secondary : ink,
          ),
        ),
      ),
    );
  }
}

class PublicMarketingSurface extends StatelessWidget {
  const PublicMarketingSurface({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Theme(
    data: CollectPublicMarketingTheme.light(),
    child: Builder(builder: builder),
  );
}
