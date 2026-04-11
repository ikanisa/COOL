import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_icon_box.dart';

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    final items = [
      (
        icon: Icons.add_rounded,
        label: l10n.save,
        route: AppRoutes.contributionCircles,
        accent: colors.accent,
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        label: l10n.homeQuickScanUpper,
        route: AppRoutes.scannerLocation(),
        accent: colors.info,
      ),
      (
        icon: Icons.center_focus_strong_rounded,
        label: l10n.homeQuickBiopayLabel,
        route: AppRoutes.biopayScanLocation(mode: 'pay'),
        accent: colors.success,
      ),
      (
        icon: Icons.nfc_rounded,
        label: l10n.nfc,
        route: AppRoutes.biopayNfc,
        accent: colors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - CoolSpace.x3) / 2;
        return Wrap(
          spacing: CoolSpace.x3,
          runSpacing: CoolSpace.x3,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _HomeQuickActionTile(
                  icon: item.icon,
                  label: item.label,
                  accent: item.accent,
                  onTap: () => openQuickActionRoute(context, item.route),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HomeQuickActionTile extends StatelessWidget {
  const _HomeQuickActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      button: true,
      label: label,
      child: CoolCard(
        onTap: onTap,
        cardPadding: CoolCardPadding.none,
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CoolIconBox(
                  icon: icon,
                  accent: accent,
                  size: CoolIconBoxSize.md,
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: colors.tertiaryText,
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.coolText.headline(
                Theme.of(context).textTheme.titleMedium,
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
