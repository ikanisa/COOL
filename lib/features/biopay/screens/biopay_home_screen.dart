import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../widgets/biopay_surface.dart';

class BiopayHomeScreen extends StatelessWidget {
  const BiopayHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final colors = context.coolSemanticColors;

    return BiopayLightScaffold(
      topPadding: CoolSpace.x3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _ProfileAction(
              onTap: () => context.push(AppRoutes.biopayProfile),
            ),
          ),
          SizedBox(height: space.x4),
          Text(
            'Pay & Get Paid\nInstantly',
            style: context.coolText.headline(
              Theme.of(context).textTheme.displayMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.2,
              height: 0.98,
            ),
          ),
          SizedBox(height: space.x7),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - space.x4) / 2;
              return Wrap(
                spacing: space.x4,
                runSpacing: space.x4,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icons.center_focus_strong_rounded,
                      iconColor: colors.accent,
                      label: 'Face Scan',
                      onTap: () =>
                          context.push(AppRoutes.biopayScanLocation(mode: 'pay')),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icons.nfc_rounded,
                      iconColor: colors.accentDeep,
                      label: 'NFC Tap',
                      onTap: () => context.push(AppRoutes.biopayNfc),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icons.qr_code_2_rounded,
                      iconColor: colors.warning,
                      label: 'Get QR',
                      onTap: () => context.push(AppRoutes.biopayQr),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _BiopayActionTile(
                      icon: Icons.qr_code_scanner_rounded,
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

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.circular(CoolRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.person_outline_rounded,
            color: colors.secondaryText,
            size: 28,
          ),
        ),
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

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.circular(CoolRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        child: Container(
          height: 220,
          padding: const EdgeInsets.all(CoolSpace.x5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.xl),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 38, color: iconColor),
              ),
              const Spacer(),
              Text(
                label,
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
    );
  }
}
