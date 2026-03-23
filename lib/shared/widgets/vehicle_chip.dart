import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

class VehicleChip extends StatelessWidget {
  const VehicleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label filter',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: CoolMotion.quick,
          padding: const EdgeInsets.symmetric(
            horizontal: CoolSpace.x4,
            vertical: CoolSpace.x2 + 1,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.chipSelectedBackground
                : colors.cardSurfaceStrong,
            borderRadius: const BorderRadius.all(
              Radius.circular(CoolRadii.pill),
            ),
            boxShadow: isSelected
                ? CoolShadows.floating(
                    Theme.of(context).brightness,
                    strength: 0.2,
                  )
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              color: isSelected
                  ? colors.accentForeground
                  : colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
