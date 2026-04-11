import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_quick_action_grid.dart';

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    return CoolQuickActionGrid(
      actions: [
        CoolQuickAction(
          icon: Icons.add_rounded,
          label: l10n.save,
          accent: colors.accent,
          onTap: () => openQuickActionRoute(context, AppRoutes.contributionCircles),
        ),
        CoolQuickAction(
          icon: Icons.qr_code_scanner_rounded,
          label: l10n.homeQuickScanUpper,
          accent: colors.info,
          onTap: () => openQuickActionRoute(context, AppRoutes.scannerLocation()),
        ),
        CoolQuickAction(
          icon: Icons.center_focus_strong_rounded,
          label: l10n.homeQuickBiopayLabel,
          accent: colors.success,
          onTap: () => openQuickActionRoute(context, AppRoutes.biopayScanLocation(mode: 'pay')),
        ),
        CoolQuickAction(
          icon: Icons.nfc_rounded,
          label: l10n.nfc,
          accent: colors.warning,
          onTap: () => openQuickActionRoute(context, AppRoutes.biopayNfc),
        ),
      ],
    );
  }
}

