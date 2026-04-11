import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_quick_action_grid.dart';
import '../widgets/biopay_surface.dart';

class BiopayHomeScreen extends StatelessWidget {
  const BiopayHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final space = context.coolSpace;
    final colors = context.coolSemanticColors;

    return BiopayLightScaffold(
      topPadding: CoolSpace.x2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.x3),
          Text(
            l10n.navBiopay,
            style: context.coolText.mobiLabel(color: colors.secondaryText),
          ),
          SizedBox(height: space.x2),
          Text(
            l10n.biopayHomeHeadline,
            style: context.coolText.headline(
              Theme.of(context).textTheme.headlineMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          SizedBox(height: space.x4),
          CoolQuickActionGrid(
            actions: [
              CoolQuickAction(
                icon: CoolIcons.faceScan,
                label: l10n.biopayFaceScanLabel,
                accent: colors.accent,
                onTap: () => context.push(
                  AppRoutes.biopayScanLocation(mode: 'pay'),
                ),
              ),
              CoolQuickAction(
                icon: CoolIcons.nfc,
                label: l10n.biopayNfcTapLabel,
                accent: colors.accentDeep,
                iconWidget: SvgPicture.asset(
                  'assets/icons/biopay_nfc.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    colors.accentDeep,
                    BlendMode.srcIn,
                  ),
                ),
                onTap: () => context.push(AppRoutes.biopayNfc),
              ),
              CoolQuickAction(
                icon: CoolIcons.qrCode,
                label: l10n.generateQr,
                accent: colors.warning,
                onTap: () => context.push(AppRoutes.biopayQr),
              ),
              CoolQuickAction(
                icon: CoolIcons.qrScan,
                label: l10n.scanQr,
                accent: colors.info,
                onTap: () => context.push(AppRoutes.scannerLocation()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

