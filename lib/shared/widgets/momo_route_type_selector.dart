import 'package:flutter/material.dart';

import '../../core/config/country_catalog.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';

/// Two-option selector for choosing the default MoMo receive route.
class MomoRouteTypeSelector extends StatelessWidget {
  const MomoRouteTypeSelector({
    required this.value,
    required this.onChanged,
    this.phoneLabel,
    this.codeLabel,
    super.key,
  });

  final MomoRecipientType value;
  final ValueChanged<MomoRecipientType> onChanged;
  final String? phoneLabel;
  final String? codeLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x1),
      decoration: BoxDecoration(
        color: colors.routeSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MomoRouteTypeOption(
              label: phoneLabel ?? l10n.momoNumber1,
              isActive: value == MomoRecipientType.phoneNumber,
              onTap: () => onChanged(MomoRecipientType.phoneNumber),
            ),
          ),
          const SizedBox(width: CoolSpace.x1),
          Expanded(
            child: _MomoRouteTypeOption(
              label: codeLabel ?? l10n.momoCode,
              isActive: value == MomoRecipientType.code,
              onTap: () => onChanged(MomoRecipientType.code),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomoRouteTypeOption extends StatelessWidget {
  const _MomoRouteTypeOption({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final radius = BorderRadius.circular(CoolRadii.lg);
    final activeBackground = brightness == Brightness.dark
        ? colors.overlaySurface.withValues(alpha: 0.9)
        : Colors.white;

    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(vertical: CoolSpace.x4),
            decoration: BoxDecoration(
              color: isActive ? activeBackground : Colors.transparent,
              borderRadius: radius,
              boxShadow: isActive
                  ? CoolShadows.standard(brightness, strength: 0.32)
                  : const <BoxShadow>[],
            ),
            alignment: Alignment.center,
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: isActive ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
