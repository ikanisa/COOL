import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// Standardized toast/snackbar for the Cool app.
///
/// Provides three themed variants with consistent styling, haptic feedback,
/// and auto-dismiss. Replaces raw `ScaffoldMessenger.showSnackBar` usage.
///
/// ```dart
/// CoolToast.success(context, 'Trip booked successfully!');
/// CoolToast.error(context, 'Payment failed. Please try again.');
/// CoolToast.info(context, 'Your profile was updated.');
/// ```
abstract final class CoolToast {
  /// Green accent toast for successful operations.
  static void success(BuildContext context, String message) {
    _show(context, message: message, variant: _Variant.success);
  }

  /// Red toast for errors that need user attention.
  static void error(BuildContext context, String message) {
    _show(context, message: message, variant: _Variant.error);
  }

  /// Blue toast for informational messages.
  static void info(BuildContext context, String message) {
    _show(context, message: message, variant: _Variant.info);
  }

  static void _show(
    BuildContext context, {
    required String message,
    required _Variant variant,
  }) {
    // Dismiss any existing snackbar first.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final config = _config(variant);

    // Haptic feedback for success and error.
    if (variant == _Variant.success || variant == _Variant.error) {
      HapticFeedback.lightImpact();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(config.icon, color: config.color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: config.color.withValues(alpha: 0.3)),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: variant == _Variant.error
            ? const Duration(seconds: 4)
            : const Duration(seconds: 3),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  static _VariantConfig _config(_Variant variant) {
    return switch (variant) {
      _Variant.success => const _VariantConfig(
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.accent,
      ),
      _Variant.error => const _VariantConfig(
        icon: Icons.error_outline_rounded,
        color: AppColors.red,
      ),
      _Variant.info => const _VariantConfig(
        icon: Icons.info_outline_rounded,
        color: AppColors.blue,
      ),
    };
  }
}

enum _Variant { success, error, info }

class _VariantConfig {
  const _VariantConfig({required this.icon, required this.color});
  final IconData icon;
  final Color color;
}
