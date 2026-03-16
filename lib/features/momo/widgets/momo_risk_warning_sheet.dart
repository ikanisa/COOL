import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/momo_risk_provider.dart';

class MomoRiskWarningSheet extends StatelessWidget {
  const MomoRiskWarningSheet({
    required this.risk,
    super.key,
  });

  final MomoRiskResult risk;

  static Future<bool?> show(BuildContext context, MomoRiskResult risk) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => MomoRiskWarningSheet(risk: risk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        decoration: BoxDecoration(
          color: palette.bg.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: palette.border.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 32),
            
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.gpp_maybe_rounded,
                color: AppColors.orange,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              risk.warningTitle.isEmpty ? 'Guardian AI Check' : risk.warningTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              risk.warningBody.isEmpty ? risk.reason : risk.warningBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: palette.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            CoolCard(
              backgroundColor: palette.surface2,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: AppColors.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This check helps prevent mistaken transfers and fraud.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            CoolButton(
              label: 'Proceed Anyway',
              variant: CoolButtonVariant.secondary,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 12),
            CoolButton(
              label: 'Cancel & Review',
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
