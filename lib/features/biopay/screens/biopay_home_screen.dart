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
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: BiopaySurfaceColors.text,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.2,
              height: 0.98,
            ),
          ),
          SizedBox(height: space.x7),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: space.x4,
            crossAxisSpacing: space.x4,
            childAspectRatio: 0.94,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _BiopayActionTile(
                icon: Icons.center_focus_strong_rounded,
                iconColor: BiopaySurfaceColors.primary,
                label: 'Face Scan',
                onTap: () =>
                    context.push(AppRoutes.biopayScanLocation(mode: 'pay')),
              ),
              _BiopayActionTile(
                icon: Icons.nfc_rounded,
                iconColor: BiopaySurfaceColors.purple,
                label: 'NFC Tap',
                onTap: () => context.push(AppRoutes.biopayNfc),
              ),
              _BiopayActionTile(
                icon: Icons.qr_code_2_rounded,
                iconColor: BiopaySurfaceColors.orange,
                label: 'Get QR',
                onTap: () => context.push(AppRoutes.biopayQr),
              ),
              _BiopayActionTile(
                icon: Icons.qr_code_scanner_rounded,
                iconColor: BiopaySurfaceColors.teal,
                label: 'Scan QR',
                onTap: () => context.push(AppRoutes.scannerLocation()),
              ),
            ],
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
    return Material(
      color: BiopaySurfaceColors.surfaceMuted,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: BiopaySurfaceColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.person_outline_rounded,
            color: BiopaySurfaceColors.mutedText,
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
    return Material(
      color: BiopaySurfaceColors.surfaceMuted,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: const EdgeInsets.all(CoolSpace.x5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: BiopaySurfaceColors.shadow,
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 38, color: iconColor),
              ),
              const Spacer(),
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: BiopaySurfaceColors.text,
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
