import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';

/// Standardized toast/snackbar for the Cool app.
///
/// Provides three themed variants with consistent styling, haptic feedback,
/// and auto-dismiss. Replaces raw `ScaffoldMessenger.showSnackBar` usage.
///
/// ```dart
/// CoolToast.success(context, 'Contribution confirmed!');
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

    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final config = _config(variant, colors);
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
                const SizedBox(width: CoolSpace.x3),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        backgroundColor: colors.cardSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.sm),
          side: BorderSide(color: config.color.withValues(alpha: 0.3)),
        ),
        margin: const EdgeInsets.fromLTRB(
          CoolSpace.x4,
          0,
          CoolSpace.x4,
          CoolSpace.x4,
        ),
        duration: variant == _Variant.error
            ? const Duration(seconds: 4)
            : const Duration(seconds: 3),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  static _VariantConfig _config(_Variant variant, CoolSemanticColors colors) {
    return switch (variant) {
      _Variant.success => _VariantConfig(
        icon: Icons.check_circle_outline_rounded,
        color: colors.accent,
      ),
      _Variant.error => _VariantConfig(
        icon: Icons.error_outline_rounded,
        color: colors.danger,
      ),
      _Variant.info => _VariantConfig(
        icon: Icons.info_outline_rounded,
        color: colors.info,
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
