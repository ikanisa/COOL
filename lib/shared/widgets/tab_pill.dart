import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

class TabPill extends StatelessWidget {
  const TabPill({
    required this.label,
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final brightness = theme.brightness;
    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.chipSelectedBackground
                  : colors.chipBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(
                color: isActive ? colors.accent : colors.border,
              ),
              boxShadow: isActive
                  ? CoolShadows.clay(brightness, strength: 0.4)
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                color: isActive ? colors.primaryText : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
