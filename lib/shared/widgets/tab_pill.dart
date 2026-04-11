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
    final activeBackground = colors.chipSelectedBackground;
    final inactiveBackground = colors.chipBackground;
    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? activeBackground : inactiveBackground,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
              border: Border.all(
                color: isActive
                    ? colors.accent.withValues(alpha: 0.24)
                    : colors.border,
              ),
              boxShadow: isActive
                  ? CoolShadows.primary(strength: 0.4)
                  : const <BoxShadow>[],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? colors.primaryText : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
