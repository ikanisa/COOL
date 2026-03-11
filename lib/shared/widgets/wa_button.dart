import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A WhatsApp-branded action button.
///
/// Rendered as a compact pill with the WhatsApp green tint, a 💬 icon
/// prefix, and a customisable [label] (defaults to "WhatsApp").
class WaButton extends StatelessWidget {
  const WaButton({required this.onTap, this.label = 'WhatsApp', super.key});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.whatsapp.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.whatsapp),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.whatsapp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
