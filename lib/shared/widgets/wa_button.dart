import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/app_colors.dart';

/// A compact WhatsApp-branded icon button.
///
/// Rendered as a small green-tinted circle with a chat icon.
/// Text stays optional for places that still need a visible label.
class WaButton extends StatelessWidget {
  const WaButton({
    required this.onTap,
    this.label = 'WhatsApp',
    this.iconOnly = true,
    this.fullWidth = false,
    super.key,
  });

  final VoidCallback onTap;
  final String label;
  final bool iconOnly;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: iconOnly ? CoolTapTargets.minimum : null,
            height: CoolTapTargets.minimum,
            padding: iconOnly
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: iconOnly
                  ? AppColors.whatsapp.withValues(alpha: 0.14)
                  : AppColors.whatsapp,
              shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: iconOnly ? null : BorderRadius.circular(18),
              border: Border.all(
                color: iconOnly
                    ? AppColors.whatsapp
                    : colors.highlightColor.withValues(alpha: 0.16),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.whatsapp.withValues(
                    alpha: iconOnly ? 0.12 : 0.26,
                  ),
                  blurRadius: iconOnly ? 12 : 22,
                  spreadRadius: iconOnly ? -6 : -10,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_rounded,
                  size: 18,
                  color: iconOnly ? AppColors.whatsapp : Colors.white,
                ),
                if (!iconOnly) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (!iconOnly) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: colors.highlightColor.withValues(alpha: 0.9),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
