import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// Variants available for [CoolButton].
enum CoolButtonVariant { primary, secondary }

/// A styled button used throughout the Cool app.
///
/// Supports two visual variants ([CoolButtonVariant.primary] and
/// [CoolButtonVariant.secondary]), an optional leading [icon], and a
/// built-in loading state that swaps the label for a spinner.
class CoolButton extends StatelessWidget {
  const CoolButton({
    required this.label,
    required this.onTap,
    this.variant = CoolButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final CoolButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final IconData? icon;

  // ── Constants ───────────────────────────────────────────────────────
  static const _height = 52.0;
  static const _radius = 12.0;
  static const _fontSize = 15.0;

  bool get _isPrimary => variant == CoolButtonVariant.primary;

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading;
    final backgroundDecoration = BoxDecoration(
      gradient: _isPrimary && enabled
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.accent2],
            )
          : !_isPrimary
          ? AppColors.cardGradient
          : null,
      color: _isPrimary
          ? (enabled ? null : AppColors.surface3)
          : AppColors.surface2,
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(
        color: _isPrimary
            ? (enabled
                  ? AppColors.accent2.withValues(alpha: 0.45)
                  : AppColors.border)
            : (enabled ? AppColors.border2 : AppColors.border),
      ),
      boxShadow: [
        if (_isPrimary && enabled)
          BoxShadow(
            color: AppColors.accentGlow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        BoxShadow(
          color: Colors.black.withValues(alpha: enabled ? 0.2 : 0.1),
          blurRadius: enabled ? 18 : 10,
          offset: const Offset(0, 10),
        ),
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: _height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: Ink(
          decoration: backgroundDecoration,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onTap();
                  }
                : null,
            borderRadius: BorderRadius.circular(_radius),
            splashColor: _isPrimary
                ? Colors.black.withValues(alpha: 0.08)
                : AppColors.accentGlow,
            highlightColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: _buildChild(enabled),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChild(bool enabled) {
    if (isLoading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.accent,
        ),
      );
    }

    final textColor = _isPrimary
        ? Colors.black
        : (enabled ? AppColors.text : AppColors.text3);

    final textWidget = Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: _fontSize,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );

    if (icon == null) return textWidget;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: textColor),
        const SizedBox(width: 8),
        textWidget,
      ],
    );
  }
}
