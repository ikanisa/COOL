import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
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
            l10n.biopayHomeHeadline,
            style: context.coolText.headline(
              Theme.of(context).textTheme.displayMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -2.2,
              height: 0.98,
            ),
          ),
          SizedBox(height: space.x5),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - space.x3) / 2;
              return Wrap(
                spacing: space.x3,
                runSpacing: space.x3,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icon(
                        Icons.center_focus_strong_rounded,
                        size: 34,
                        color: colors.accent,
                      ),
                      iconColor: colors.accent,
                      label: l10n.biopayFaceScanLabel,
                      onTap: () => context.push(
                        AppRoutes.biopayScanLocation(mode: 'pay'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: SvgPicture.asset(
                        'assets/icons/biopay_nfc.svg',
                        width: 34,
                        height: 34,
                        colorFilter: ColorFilter.mode(
                          colors.accentDeep,
                          BlendMode.srcIn,
                        ),
                      ),
                      iconColor: colors.accentDeep,
                      label: l10n.biopayNfcTapLabel,
                      onTap: () => context.push(AppRoutes.biopayNfc),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icon(
                        Icons.qr_code_2_rounded,
                        size: 34,
                        color: colors.warning,
                      ),
                      iconColor: colors.warning,
                      label: l10n.generateQr,
                      onTap: () => context.push(AppRoutes.biopayQr),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 34,
                        color: colors.info,
                      ),
                      iconColor: colors.info,
                      label: l10n.scanQr,
                      onTap: () => context.push(AppRoutes.scannerLocation()),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BiopayActionTile extends StatelessWidget {
  const _BiopayActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tileHeight = 200.0 + (textScale > 1 ? (textScale - 1) * 64.0 : 0.0);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CoolRadii.xl),
          child: Container(
            height: tileHeight,
            padding: const EdgeInsets.all(CoolSpace.x4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CoolRadii.xl),
              boxShadow: CoolShadows.ambientFloat(strength: 0.3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.headlineSmall,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
