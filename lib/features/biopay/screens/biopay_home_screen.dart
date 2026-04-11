import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_icon_box.dart';
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
              Theme.of(context).textTheme.displaySmall,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          SizedBox(height: space.x4),
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
    final tileHeight = 146.0 + (textScale > 1 ? (textScale - 1) * 42.0 : 0.0);
    return Semantics(
      button: true,
      label: label,
      child: CoolCard(
        onTap: onTap,
        cardPadding: CoolCardPadding.none,
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: SizedBox(
          height: tileHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CoolIconBox(
                    icon: Icons.circle,
                    accent: iconColor,
                    size: CoolIconBoxSize.lg,
                    iconWidget: icon,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: colors.tertiaryText,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                style: context.coolText.headline(
                  Theme.of(context).textTheme.titleMedium,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
