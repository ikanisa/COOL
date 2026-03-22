import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

/// Variants available for [CoolButton].
enum CoolButtonVariant { primary, secondary }

/// A styled button used throughout the COOL app.
class CoolButton extends StatefulWidget {
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
  final String? semanticsLabel;

  @override
  State<CoolButton> createState() => _CoolButtonState();
}

class _CoolButtonState extends State<CoolButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final brightness = theme.brightness;
    final enabled = !widget.isLoading;
    final isPrimary = widget.variant == CoolButtonVariant.primary;

    final backgroundDecoration = BoxDecoration(
      color: isPrimary
          ? (enabled ? null : palette.surface3)
          : (enabled
                ? colors.buttonSecondaryBackground
                : colors.chipBackground),
      gradient: isPrimary && enabled ? colors.accentGradient : null,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      border: Border.all(
        color: isPrimary
            ? (enabled
                  ? Colors.white.withValues(alpha: 0.14)
                  : colors.border.withValues(alpha: 0.6))
            : (enabled ? colors.borderStrong : colors.border),
        width: isPrimary ? 1.0 : 1.1,
      ),
      boxShadow: enabled
          ? (isPrimary
                ? CoolShadows.floating(brightness, strength: 0.72)
                : CoolShadows.clay(brightness, strength: 0.55))
          : null,
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Semantics(
          label: widget.semanticsLabel ?? widget.label,
          button: true,
          enabled: enabled,
          hint: widget.isLoading ? 'Loading' : null,
          excludeSemantics: true,
          child: Tooltip(
            message: widget.semanticsLabel ?? widget.label,
            child: SizedBox(
              width: widget.fullWidth ? double.infinity : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: CoolTapTargets.comfortable,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  child: Ink(
                    decoration: backgroundDecoration,
                    child: InkWell(
                      onTapDown: (_) => _scaleController.forward(),
                      onTapUp: (_) => _scaleController.reverse(),
                      onTapCancel: () => _scaleController.reverse(),
                      onTap: enabled
                          ? () {
                              if (isPrimary) {
                                HapticFeedback.mediumImpact();
                              } else {
                                HapticFeedback.lightImpact();
                              }
                              widget.onTap();
                            }
                          : null,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      splashColor: isPrimary
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.1)
                          : colors.primaryText.withValues(alpha: 0.08),
                      highlightColor: Colors.transparent,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: isPrimary || !enabled
                              ? null
                              : LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    colors.highlightColor.withValues(
                                      alpha: brightness == Brightness.light
                                          ? 0.38
                                          : 0.04,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 16,
                          ),
                          child: _buildChild(context, palette, enabled),
                        ),
                      ),
                    ),
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
    final textColor = widget.variant == CoolButtonVariant.primary
        ? Theme.of(context).colorScheme.onPrimary
        : (enabled ? context.coolSemanticColors.primaryText : palette.text3);

    Widget child;
    if (widget.isLoading) {
      child = CupertinoActivityIndicator(
        key: const ValueKey('cool_button_loading'),
        radius: 11,
        color: textColor,
      );
    } else {
      final textWidget = Text(
        widget.label,
        maxLines: 2,
        softWrap: true,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style:
            Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 16.0,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: -0.2,
            ) ??
            GoogleFonts.manrope(
              fontSize: 16.0,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: -0.2,
            ),
      );

      if (widget.icon == null) {
        child = textWidget;
      } else {
        child = Wrap(
          key: const ValueKey('cool_button_content'),
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(widget.icon, size: 20, color: textColor),
            textWidget,
          ],
        );
      }
    }

    return AnimatedSwitcher(
      duration: CoolMotion.quick,
      child: Container(key: ValueKey(widget.isLoading), child: child),
    );
  }
}
