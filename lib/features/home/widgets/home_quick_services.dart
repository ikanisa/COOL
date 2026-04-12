import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_icon_box.dart';

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    return Row(
      children: [
        _HomeQuickServiceAction(
          icon: CoolIcons.add,
          label: l10n.save,
          accent: colors.accent,
          onTap: () => openQuickActionRoute(context, AppRoutes.groups),
        ),
        const SizedBox(width: CoolSpace.x3),
        _HomeQuickServiceAction(
          icon: CoolIcons.qrScan,
          label: l10n.homeQuickScanUpper,
          accent: colors.info,
          onTap: () =>
              openQuickActionRoute(context, AppRoutes.scannerLocation()),
        ),
        const SizedBox(width: CoolSpace.x3),
        _HomeQuickServiceAction(
          icon: CoolIcons.faceScan,
          label: l10n.homeQuickBiopayLabel,
          accent: colors.success,
          onTap: () => openQuickActionRoute(
            context,
            AppRoutes.biopayScanLocation(mode: 'pay'),
          ),
        ),
        const SizedBox(width: CoolSpace.x3),
        _HomeQuickServiceAction(
          icon: CoolIcons.nfc,
          label: l10n.nfc,
          accent: colors.warning,
          iconWidget: SvgPicture.asset(
            'assets/icons/biopay_nfc.svg',
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(colors.warning, BlendMode.srcIn),
          ),
          onTap: () => openQuickActionRoute(context, AppRoutes.biopayNfc),
        ),
      ],
    );
  }
}

class _HomeQuickServiceAction extends StatelessWidget {
  const _HomeQuickServiceAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.iconWidget,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CoolRadii.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: CoolSpace.x2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CoolIconBox(
                    icon: icon,
                    accent: accent,
                    size: CoolIconBoxSize.md,
                    iconWidget: iconWidget,
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.coolText
                        .mobiLabel(color: colors.primaryText)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
