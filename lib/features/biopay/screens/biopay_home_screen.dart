import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/atmospheric_background.dart';

/// BioPay Hub screen — 3 full-width payment method cards stacked vertically.
///
/// Layout: hero text ("HOW DO YOU / WANT TO PAY?") + 3 cards:
///   1. Face Scan (blue accent)
///   2. NFC Scan  (gold accent, gold gradient tint)
///   3. QR Scan   (blue accent)
class BiopayHomeScreen extends StatelessWidget {
  const BiopayHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: Stack(
        children: [
          const AtmosphericBackground(showGrid: true),
          CustomScrollView(
            slivers: [
              // ── Header ─────────────────────────────────────────
              SliverAppBar(
                pinned: true,
                backgroundColor: colors.appBackground.withValues(alpha: 0.80),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: CoolSpace.x10,
                leading: IconButton(
                  onPressed: () => context.pop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.primaryText,
                  ),
                ),
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: CoolBlur.heavy,
                      sigmaY: CoolBlur.heavy,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colors.border.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      padding: EdgeInsets.only(
                        top: MediaQuery.viewPaddingOf(context).top,
                      ),
                      child: Text(
                        'BioPay Hub',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Content ────────────────────────────────────────
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  space.x5,
                  space.x8,
                  space.x5,
                  space.x8 + bottomPadding,
                ),
                sliver: SliverList.list(
                  children: [
                    // ── Hero text ──
                    Text(
                      'HOW DO YOU',
                      style: context.coolText.rayonCondensed(
                        theme.textTheme.displayMedium,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      'WANT TO PAY?',
                      style: context.coolText.rayonCondensed(
                        theme.textTheme.displayMedium,
                        fontWeight: FontWeight.w900,
                        color: RsColors.rsBlue,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),

                    SizedBox(height: space.x8),

                    // ── Face Scan card ──
                    _BioPayMethodCard(
                      icon: Icons.face_retouching_natural_rounded,
                      title: 'FACE\nSCAN',
                      subtitle: 'SCAN FACE TO\nPAY',
                      accentColor: RsColors.rsBlue,
                      onTap: () => context.push(
                        AppRoutes.biopayScanLocation(mode: 'pay'),
                      ),
                    ),

                    const SizedBox(height: CoolSpace.x4),

                    // ── NFC Scan card (gold gradient tint) ──
                    _BioPayMethodCard(
                      icon: Icons.nfc_rounded,
                      title: 'NFC\nSCAN',
                      subtitle: 'PHONE TO\nPHONE',
                      accentColor: RsColors.rsGold,
                      hasGoldGradient: true,
                      onTap: () => context.push(AppRoutes.biopayNfc),
                    ),

                    const SizedBox(height: CoolSpace.x4),

                    // ── QR Scan card ──
                    _BioPayMethodCard(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'QR\nSCAN',
                      subtitle: 'SCAN TO PAY',
                      accentColor: RsColors.rsBlue,
                      onTap: () =>
                          context.push('${AppRoutes.scanner}?mode=momo'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-width payment method card
// ─────────────────────────────────────────────────────────────────────────────

class _BioPayMethodCard extends StatelessWidget {
  const _BioPayMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.hasGoldGradient = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final bool hasGoldGradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xl)),
        child: AnimatedContainer(
          duration: CoolMotion.quick,
          padding: const EdgeInsets.all(CoolSpace.x6),
          decoration: BoxDecoration(
            // Dark card surface with optional gold gradient tint
            gradient: hasGoldGradient
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.06),
                      RsColors.rsGold.withValues(alpha: 0.08),
                      RsColors.rsGold.withValues(alpha: 0.12),
                    ],
                  )
                : null,
            color: hasGoldGradient
                ? null
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xl)),
            border: Border.all(
              color: hasGoldGradient
                  ? RsColors.rsGold.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              // ── Icon box ──
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 28, color: accentColor),
              ),

              const SizedBox(width: CoolSpace.x5),

              // ── Title + subtitle ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.coolText.rayonCondensed(
                        theme.textTheme.headlineMedium,
                        fontWeight: FontWeight.w800,
                        height: 0.95,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      subtitle,
                      style: context.coolText.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText.withValues(alpha: 0.5),
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Chevron ──
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: colors.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
