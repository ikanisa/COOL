import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A compact WhatsApp-branded icon button.
///
/// Rendered as a small green-tinted circle with a chat icon.
/// Text stays optional for places that still need a visible label.
class WaButton extends StatelessWidget {
  /// Fixed WhatsApp brand color (external brand, not theme-dependent).
  static const _whatsApp = Color(0xFF2E8A57);
  const WaButton({
    required this.onTap,
    this.label = 'WhatsApp',
    this.iconOnly = true,
    this.fullWidth = false,
    super.key,
  });

  final VoidCallback? onTap;
  final String label;
  final bool iconOnly;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final isEnabled = onTap != null;
    final shape = iconOnly
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CoolRadii.sm),
          );
    final backgroundColor = iconOnly
        ? (isEnabled
              ? _whatsApp.withValues(alpha: 0.14)
              : colors.cardSurfaceStrong)
        : (isEnabled ? _whatsApp : colors.buttonSecondaryBackground);
    final borderColor = isEnabled
        ? (iconOnly ? _whatsApp : colors.highlightColor.withValues(alpha: 0.16))
        : colors.border;
    final foregroundColor = isEnabled
        ? (iconOnly ? _whatsApp : Colors.white)
        : colors.tertiaryText;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: Material(
          color: Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: iconOnly ? CoolTapTargets.minimum : null,
            height: CoolTapTargets.minimum,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: BorderSide(color: borderColor)),
              color: backgroundColor,
              shadows: isEnabled
                  ? CoolShadows.floating(
                      theme.brightness,
                      strength: iconOnly ? 0.26 : 0.4,
                    )
                  : const <BoxShadow>[],
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: iconOnly
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_rounded, size: 18, color: foregroundColor),
                    if (!iconOnly) ...[
                      const SizedBox(width: CoolSpace.x2),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: foregroundColor,
                          ),
                        ),
                      ),
                    ],
                    if (!iconOnly) ...[
                      const SizedBox(width: CoolSpace.x2),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: isEnabled
                            ? colors.highlightColor.withValues(alpha: 0.9)
                            : colors.tertiaryText,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
