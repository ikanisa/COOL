import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';

/// A pill-shaped tab selector used in horizontal filter rows.
///
/// Active state uses an accent glow background and accent border;
/// inactive uses the default surface2 + border treatment.
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
    final palette = context.coolPalette;
    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isActive ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? palette.accent : palette.text2,
            ),
          ),
        ),
      ),
    );
  }
}
