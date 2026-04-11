import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;

    // Items resolved at build time so they can reference theme tokens.
    final items = [
      (
        icon: Icons.add_rounded,
        label: l10n.save.toUpperCase(),
        route: AppRoutes.contributionCircles,
        accent: colors.accent,
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        label: l10n.homeQuickScanUpper,
        route: AppRoutes.scannerLocation(),
        accent: colors.accentDeep, // per-feature brand accent
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

    return Row(
      children: [
        for (final (index, item) in items.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == items.length - 1 ? 0 : CoolSpace.x3,
              ),
              child: _HomeQuickActionTile(
                icon: item.icon,
                label: item.label,
                accent: item.accent,
                onTap: () => openQuickActionRoute(context, item.route),
              ),
            ),
          ),
      ],
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
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            // Glassmorphic tile
            ClipRRect(
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CoolBlur.glass,
                  sigmaY: CoolBlur.glass,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[colors.glassSurface, colors.cardSurface],
                    ),
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    boxShadow: CoolShadows.ambientFloat(strength: 0.5),
                  ),
                  child: SizedBox(
                    height: 76,
                    child: Stack(
                      children: [
                        // Inner top-edge specular highlight
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 28,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(CoolRadii.lg),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  colors.glassSurface,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Icon with accent tint background
                        Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(CoolRadii.md),
                            ),
                            child: Center(
                              child: Icon(icon, color: accent, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                fontWeight: FontWeight.w800,
                color: colors.secondaryText,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
