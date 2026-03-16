import 'package:flutter/material.dart';

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
    super.key,
  });

  final VoidCallback onTap;
  final String label;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: iconOnly ? 40 : null,
          height: 40,
          padding: iconOnly
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.whatsapp.withValues(alpha: 0.12),
            shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: iconOnly ? null : BorderRadius.circular(20),
            border: Border.all(color: AppColors.whatsapp),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.call_rounded,
                size: 18,
                color: AppColors.whatsapp,
              ),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.whatsapp,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
