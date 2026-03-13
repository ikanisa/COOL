import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config/country_catalog.dart';
import '../../core/theme/app_colors.dart';

/// Two-option selector for choosing the default MoMo receive route.
class MomoRouteTypeSelector extends StatelessWidget {
  const MomoRouteTypeSelector({
    required this.value,
    required this.onChanged,
    this.phoneLabel = 'MoMo Number',
    this.codeLabel = 'MoMo Code',
    super.key,
  });

  final MomoRecipientType value;
  final ValueChanged<MomoRecipientType> onChanged;
  final String phoneLabel;
  final String codeLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MomoRouteTypeOption(
            label: phoneLabel,
            isActive: value == MomoRecipientType.phoneNumber,
            onTap: () => onChanged(MomoRecipientType.phoneNumber),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MomoRouteTypeOption(
            label: codeLabel,
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
    return Semantics(
      button: true,
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accentGlow : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.accent : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.accent : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
