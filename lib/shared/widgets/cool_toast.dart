import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';

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

    final palette = context.coolPalette;
    final config = _config(variant, palette);
    final direction = Directionality.of(context);

    // Haptic feedback for success and error.
    if (variant == _Variant.success || variant == _Variant.error) {
      HapticFeedback.lightImpact();
    }

    if (MediaQuery.supportsAnnounceOf(context)) {
      SemanticsService.sendAnnouncement(View.of(context), message, direction);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          container: true,
          liveRegion: true,
          label: message,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(config.icon, color: config.color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        backgroundColor: palette.surface2,
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

  static _VariantConfig _config(_Variant variant, CoolPalette palette) {
    return switch (variant) {
      _Variant.success => _VariantConfig(
        icon: Icons.check_circle_outline_rounded,
        color: palette.accent,
      ),
      _Variant.error => _VariantConfig(
        icon: Icons.error_outline_rounded,
        color: palette.red,
      ),
      _Variant.info => _VariantConfig(
        icon: Icons.info_outline_rounded,
        color: palette.blue,
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
