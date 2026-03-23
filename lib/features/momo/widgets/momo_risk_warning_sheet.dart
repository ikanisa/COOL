import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/momo_risk_provider.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

class MomoRiskWarningSheet extends StatelessWidget {
  const MomoRiskWarningSheet({required this.risk, super.key});

  final MomoRiskResult risk;

  static Future<bool?> show(BuildContext context, MomoRiskResult risk) {
    return showCoolBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => MomoRiskWarningSheet(risk: risk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          CoolSpace.x6,
          CoolSpace.x3,
          CoolSpace.x6,
          CoolSpace.x8,
        ),
        decoration: BoxDecoration(
          color: colors.appBackground.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(CoolRadii.xl),
            topRight: Radius.circular(CoolRadii.xl),
          ),
          border: Border.all(color: colors.border.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderStrong,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.xs),
                ),
              ),
            ),
            SizedBox(height: space.x7),

            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.gpp_maybe_rounded,
                color: colors.warning,
                size: 32,
              ),
            ),
            SizedBox(height: space.x6),

            Text(
              risk.warningTitle.isEmpty
                  ? 'Guardian AI Check'
                  : risk.warningTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            SizedBox(height: space.x3),
            Text(
              risk.warningBody.isEmpty ? risk.reason : risk.warningBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
                height: 1.5,
              ),
            ),
            SizedBox(height: space.x7),

            CoolCard(
              backgroundColor: colors.surface,
              padding: const EdgeInsets.all(CoolSpace.x4),
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, color: colors.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This check helps prevent mistaken transfers and fraud.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: space.x7),

            CoolButton(
              label: 'Proceed Anyway',
              variant: CoolButtonVariant.secondary,
              onTap: () => Navigator.of(context).pop(true),
            ),
            SizedBox(height: space.x3),
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
