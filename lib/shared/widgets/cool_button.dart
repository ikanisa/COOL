import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';

/// Variants available for [CoolButton].
enum CoolButtonVariant { primary, secondary }

/// A styled button used throughout the Cool app.
///
/// Buttons stay visually simple so the label carries the action instead of the
/// decoration.
class CoolButton extends StatelessWidget {
  const CoolButton({
    required this.label,
    required this.onTap,
    this.variant = CoolButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.icon,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final CoolButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final IconData? icon;

  /// Custom accessibility label. Falls back to [label] if null.
  final String? semanticsLabel;

  // ── Constants ───────────────────────────────────────────────────────
  static const _height = 52.0;
  static const _radius = 14.0;
  static const _fontSize = 15.0;

  bool get _isPrimary => variant == CoolButtonVariant.primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.coolPalette;
    final enabled = !isLoading;
    final backgroundDecoration = BoxDecoration(
      color: _isPrimary
          ? (enabled ? palette.accent : palette.surface3)
          : (enabled ? palette.surface2 : palette.surface3),
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(
        color: _isPrimary
            ? (enabled ? palette.accent : palette.border)
            : (enabled ? palette.border2 : palette.border),
      ),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    return Semantics(
      label: semanticsLabel ?? label,
      button: true,
      enabled: enabled,
      hint: isLoading ? 'Loading' : null,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticsLabel ?? label,
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _height),
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
                      ? theme.colorScheme.onPrimary.withValues(alpha: 0.06)
                      : palette.text.withValues(alpha: 0.06),
                  highlightColor: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: _buildChild(context, palette, enabled),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChild(BuildContext context, CoolPalette palette, bool enabled) {
    final primaryForeground = Theme.of(context).colorScheme.onPrimary;
    final textColor = _isPrimary
        ? primaryForeground
        : (enabled ? palette.text : palette.text3);

    Widget child;
    if (isLoading) {
      child = CupertinoActivityIndicator(
        key: const ValueKey('cool_button_loading'),
        radius: 11,
        color: textColor,
      );
    } else {
      final textWidget = Text(
        label,
        maxLines: 2,
        softWrap: true,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.dmSans(
          fontSize: _fontSize,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      );

      if (icon == null) {
        child = textWidget;
      } else {
        child = Wrap(
          key: const ValueKey('cool_button_content'),
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(icon, size: 20, color: textColor),
            textWidget,
          ],
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(isLoading),
        child: child,
      ),
    );
  }
}
