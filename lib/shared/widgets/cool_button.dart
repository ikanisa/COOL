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

class _CoolButtonState extends State<CoolButton> with SingleTickerProviderStateMixin {
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
    final enabled = !widget.isLoading;
    
    final backgroundDecoration = BoxDecoration(
      color: widget.variant == CoolButtonVariant.primary
          ? (enabled ? palette.accent : palette.surface3)
          : (enabled ? palette.surface : palette.surface2),
      borderRadius: BorderRadius.circular(16.0),
      border: Border.all(
        color: widget.variant == CoolButtonVariant.primary
            ? (enabled ? Colors.white.withValues(alpha: 0.1) : palette.border)
            : (enabled ? palette.border : palette.border),
        width: 1.0,
      ),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: widget.variant == CoolButtonVariant.primary 
                    ? palette.accent.withValues(alpha: 0.15) 
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
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
                constraints: const BoxConstraints(minHeight: 56.0),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16.0),
                  child: Ink(
                    decoration: backgroundDecoration,
                    child: InkWell(
                      onTapDown: (_) => _scaleController.forward(),
                      onTapUp: (_) => _scaleController.reverse(),
                      onTapCancel: () => _scaleController.reverse(),
                      onTap: enabled
                          ? () {
                              if (widget.variant == CoolButtonVariant.primary) {
                                HapticFeedback.mediumImpact();
                              } else {
                                HapticFeedback.lightImpact();
                              }
                              widget.onTap();
                            }
                          : null,
                      borderRadius: BorderRadius.circular(16.0),
                      splashColor: widget.variant == CoolButtonVariant.primary
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.1)
                          : palette.text.withValues(alpha: 0.1),
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
        ),
      ),
    );
  }

  Widget _buildChild(BuildContext context, CoolPalette palette, bool enabled) {
    final textColor = widget.variant == CoolButtonVariant.primary
        ? Colors.white
        : (enabled ? palette.text : palette.text3);

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
        style: GoogleFonts.dmSans(
          fontSize: 17.0,
          fontWeight: FontWeight.w700,
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
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(widget.isLoading),
        child: child,
      ),
    );
  }
}

