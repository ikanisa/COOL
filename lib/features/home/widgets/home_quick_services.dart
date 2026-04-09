import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import 'home_shared.dart';

class HomeQuickServices extends StatelessWidget {
  const HomeQuickServices({super.key});

  static final _items = [
    (
      icon: Icons.add_rounded,
      label: 'SAVE',
      route: AppRoutes.contributionCircles,
      accent: HomeVisualPalette.active,
    ),
    (
      icon: Icons.qr_code_scanner_rounded,
      label: 'SCAN',
      route: AppRoutes.scannerLocation(),
      accent: const Color(0xFF9B63FF),
    ),
    (
      icon: Icons.center_focus_strong_rounded,
      label: 'BIOPAY',
      route: AppRoutes.biopayScanLocation(mode: 'pay'),
      accent: const Color(0xFF1CCB7A),
    ),
    (
      icon: Icons.nfc_rounded,
      label: 'NFC',
      route: AppRoutes.biopayNfc,
      accent: HomeVisualPalette.warning,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, item) in _items.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == _items.length - 1 ? 0 : CoolSpace.x3,
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
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Ghost glass surface
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    border: Border.all(
                      // Ghost border — crisp but subtle
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.0,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
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
                                  Colors.white.withValues(alpha: 0.12),
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
                              border: Border.all(
                                color: accent.withValues(alpha: 0.22),
                                width: 1.0,
                              ),
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
                color: HomeVisualPalette.textSecondary,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
