// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Applies status and navigation bar styles that follow the active app theme.
class ThemeSystemChrome extends StatelessWidget {
  const ThemeSystemChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Keep the legacy semantic color bridge aligned with the active theme so
    // older screens still adapt while they migrate onto direct palette reads.
    AppColors.applyBrightness(theme.brightness);

    final overlayStyle =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              statusBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              // Set to transparent for Android 15 edge-to-edge compatibility.
              // The system handles the background color automatically.
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarContrastEnforced: false,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: child,
    );
  }
}
