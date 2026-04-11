import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../widgets/biopay_surface.dart';

const _biopayNfcSvg = '''
<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="#000000"
  stroke-width="2.5"
  stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M6 8.32a7.43 7.43 0 0 1 0 7.36" />
  <path d="M9.46 6.21a11.76 11.76 0 0 1 0 11.58" />
  <path d="M12.91 4.1a15.91 15.91 0 0 1 .01 15.8" />
  <path d="M16.37 2a20.16 20.16 0 0 1 0 20" />
</svg>
''';

class BiopayHomeScreen extends StatelessWidget {
  const BiopayHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final colors = context.coolSemanticColors;

    return BiopayLightScaffold(
      topPadding: CoolSpace.x2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.x3),
          Text(
            'Pay & Get Paid\nInstantly',
            style: context.coolText.headline(
              Theme.of(context).textTheme.displayMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
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
                      label: 'Face Scan',
                      onTap: () => context.push(
                        AppRoutes.biopayScanLocation(mode: 'pay'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: SvgPicture.string(
                        _biopayNfcSvg,
                        width: 34,
                        height: 34,
                        colorFilter: ColorFilter.mode(
                          colors.accentDeep,
                          BlendMode.srcIn,
                        ),
                      ),
                      iconColor: colors.accentDeep,
                      label: 'NFC Tap',
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
                      label: 'Get QR',
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
                      label: 'Scan QR',
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
    return Material(
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
