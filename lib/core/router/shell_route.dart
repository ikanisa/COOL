import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../l10n/l10n.dart';
import '../theme/cool_foundations.dart';

/// The main scaffold that wraps all bottom-nav routes.
///
/// Tactile Monolith: 3-item floating glass pill, max 320px, accent active dot.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    required this.navigationShell,
    required this.showNavigationChrome,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final bool showNavigationChrome;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  // Tactile Monolith nav surface: frosted violet chrome
  static const _navSurfaceTop = Color(0xFF1A1640);   // Layer 1
  static const _navSurfaceBottom = Color(0xFF110E2D); // surface_dim

  late final AnimationController _entryController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Spring entry from below: y: 100 → 0
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            // Spring-like: damping 20, stiffness 100 → elasticOut approximation
            curve: const _SpringCurve(damping: 20, stiffness: 100),
          ),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  int _currentIndex() => widget.navigationShell.currentIndex;

  void _onItemTapped(int index) {
    if (index == 1) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(momoSmsRationaleProvider, (previous, next) {
      if (next.isRequestPending &&
          (previous == null || !previous.isRequestPending)) {
        MomoSmsRationaleSheet.show(
          context,
          onAccept: () => next.completeRequest(true),
          onDecline: () => next.completeRequest(false),
        );
      }
    });

    final colors = context.coolSemanticColors;
    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;
    final pillHeight = (66 + ((textScale - 1) * 12)).clamp(66, 78).toDouble();
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: widget.navigationShell),
          if (widget.showNavigationChrome)
            Positioned(
              left: CoolSpace.x4,
              right: CoolSpace.x4,
              bottom: CoolSpace.x4 + safeAreaBottom,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: _GlassPill(
                        height: pillHeight,
                        colors: colors,
                        children: [
                          _NavItem(
                            label: context.l10n.navHome,
                            icon: Icons.home_rounded,
                            isSelected: index == 0,
                            onTap: () => _onItemTapped(0),
                            colors: colors,
                          ),
                          _NavItem(
                            label: 'BioPay',
                            icon: Icons.center_focus_strong_rounded,
                            isSelected: index == 1,
                            onTap: () => _onItemTapped(1),
                            colors: colors,
                          ),
                          _NavItem(
                            label: 'Settings',
                            icon: Icons.settings_rounded,
                            isSelected: index == 2,
                            onTap: () => _onItemTapped(2),
                            colors: colors,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass Pill Container
// ─────────────────────────────────────────────────────────────────────────────

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.height,
    required this.colors,
    required this.children,
  });

  final double height;
  final CoolSemanticColors colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CoolRadii.pill),
      child: BackdropFilter(
        // Tactile Monolith glass: heavy blur for floating elements
        filter: ImageFilter.blur(
          sigmaX: CoolBlur.glass,
          sigmaY: CoolBlur.glass,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _AppShellState._navSurfaceTop,
                _AppShellState._navSurfaceBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            // No-Line Rule: no border, depth via ambient shadow
            boxShadow: CoolShadows.ambientFloat(strength: 1.0),
          ),
          child: Stack(
            children: [
              // Inner top-edge: violet-tinted highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(CoolRadii.pill),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        const Color(0xFFC4C0FF).withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x4,
                    vertical: CoolSpace.x1,
                  ),
                  child: Row(
                    children: children.map((c) => Expanded(child: c)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav Item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final activeColor = colors.accentStrong;
    final inactiveColor = colors.secondaryText.withValues(alpha: 0.70);
    final displayLabel = label.toUpperCase();

    return Material(
      color: Colors.transparent,
      child: Semantics(
        label: label,
        button: true,
        selected: isSelected,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: CoolMotion.quick,
                curve: CoolMotion.enterCurve,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  // Surface-shift for selected: no border
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.06 : 1.0,
                  duration: CoolMotion.quick,
                  curve: CoolMotion.enterCurve,
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: CoolMotion.quick,
                style: context.coolText
                    .mobiLabel(
                      color: isSelected ? activeColor : inactiveColor,
                    )
                    .copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                child: Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spring Curve (approximation of damping/stiffness spring)
// ─────────────────────────────────────────────────────────────────────────────

class _SpringCurve extends Curve {
  const _SpringCurve({required this.damping, required this.stiffness});

  final double damping;
  final double stiffness;

  @override
  double transformInternal(double t) {
    // Critically damped spring (damping=20, stiffness=100, omega=10, zeta=1).
    // Formula: 1 - (1 + omega*t) * e^(-omega*t)
    final double result = 1.0 - (1.0 + 10.0 * t) * _expNeg(10.0 * t);
    return result.clamp(0.0, 1.0);
  }

  /// Fast e^(-x) for x >= 0
  static double _expNeg(double x) {
    if (x > 20) return 0.0;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= -x / i;
      result += term;
    }
    return result.clamp(0.0, 1.0);
  }
}
