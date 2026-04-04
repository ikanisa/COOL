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
/// Mobi × Partner: 3-item floating glass pill, max 320px, gold active dot.
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
    // Pill height: ~60dp base + text scale adjustment
    final pillHeight = (60 + ((textScale - 1) * 12)).clamp(60, 72).toDouble();
    final navigationChromeInset = widget.showNavigationChrome
        ? pillHeight + CoolSpace.x8 + safeAreaBottom
        : 0.0;

    return Scaffold(
      extendBody: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: navigationChromeInset),
        child: widget.navigationShell,
      ),
      bottomNavigationBar: widget.showNavigationChrome
          ? SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  // p-8 from screen edge
                  padding: EdgeInsets.fromLTRB(
                    CoolSpace.x8,
                    0,
                    CoolSpace.x8,
                    CoolSpace.x8 + safeAreaBottom,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      // max-width: 320px
                      constraints: const BoxConstraints(maxWidth: 320),
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
                            icon: Icons.document_scanner_rounded,
                            isSelected: index == 1,
                            onTap: () => _onItemTapped(1),
                            colors: colors,
                            preserveCase: true, // BioPay exception
                          ),
                          _NavItem(
                            label: context.l10n.navProfile,
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
            )
          : null,
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
        filter: ImageFilter.blur(
          sigmaX: CoolBlur.heavy,
          sigmaY: CoolBlur.heavy,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // bg-white/5
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            // border: white/10, 1px
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1,
            ),
            // shadow-2xl shadow-black/50
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.50),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: SizedBox(
            height: height,
            // px-6 py-2
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CoolSpace.x6,
                vertical: CoolSpace.x2,
              ),
              child: Row(
                children: children.map((c) => Expanded(child: c)).toList(),
              ),
            ),
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
    this.preserveCase = false,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final CoolSemanticColors colors;
  final bool preserveCase; // BioPay exception

  @override
  Widget build(BuildContext context) {
    const activeIconColor = Colors.white;
    final inactiveIconColor = colors.secondaryText.withValues(alpha: 0.40);
    final displayLabel = preserveCase ? label : label.toUpperCase();

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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Active: bg-white/10 behind icon, scale 1.1
              AnimatedContainer(
                duration: CoolMotion.quick,
                curve: CoolMotion.enterCurve,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.1 : 1.0,
                  duration: CoolMotion.quick,
                  curve: CoolMotion.enterCurve,
                  // Icon: 18dp, stroke-width 2 (active: 2.5)
                  child: Icon(
                    icon,
                    size: 18,
                    color: isSelected ? activeIconColor : inactiveIconColor,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              // Label: 8px, JetBrains Mono, uppercase, letter-spacing 0.1em
              Text(
                displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.coolText
                    .mobiLabel(
                      color: isSelected ? Colors.white : inactiveIconColor,
                    )
                    .copyWith(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0, // ~0.1em at 8px
                    ),
              ),
              const SizedBox(height: 1),
              // Gold dot indicator below label
              AnimatedContainer(
                duration: CoolMotion.quick,
                curve: CoolMotion.enterCurve,
                width: isSelected ? 4 : 0,
                height: isSelected ? 4 : 0,
                decoration: BoxDecoration(
                  color: colors.accentGold,
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: colors.accentGold.withValues(alpha: 0.50),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
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
