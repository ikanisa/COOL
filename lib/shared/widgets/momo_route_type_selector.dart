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
    return Row(
      children: [
        Expanded(
          child: _MomoRouteTypeOption(
            label: phoneLabel ?? l10n.momoNumber1,
            isActive: value == MomoRecipientType.phoneNumber,
            onTap: () => onChanged(MomoRecipientType.phoneNumber),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MomoRouteTypeOption(
            label: codeLabel ?? l10n.momoCode,
            isActive: value == MomoRecipientType.code,
            onTap: () => onChanged(MomoRecipientType.code),
          ),
        ),
      ],
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
    const radius = BorderRadius.all(Radius.circular(CoolRadii.xs));

    return Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: CoolMotion.quick,
          padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
          decoration: BoxDecoration(
            color: isActive
                ? colors.chipSelectedBackground
                : colors.cardSurface,
            borderRadius: radius,
            border: Border.all(color: isActive ? colors.accent : colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isActive ? colors.accentForeground : colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
