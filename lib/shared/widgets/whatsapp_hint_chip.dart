import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_icons.dart';

class WhatsAppHintChip extends StatelessWidget {
  const WhatsAppHintChip({this.label = 'Chat on WhatsApp', super.key});

  /// Fixed WhatsApp brand color (external brand, not theme-dependent).
  static const _whatsApp = Color(0xFF2E8A57);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _whatsApp.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          border: Border.all(color: _whatsApp),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CoolIcons.chatBubble, size: 13, color: _whatsApp),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _whatsApp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
