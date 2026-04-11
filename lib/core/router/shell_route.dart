import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../l10n/l10n.dart';
import '../providers/connectivity_provider.dart';
import '../theme/cool_foundations.dart';

/// The main scaffold that wraps all bottom-nav routes.
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
  bool _navVisible = true;

  @override
  void initState() {
    super.initState();
    // Spring entry from below: y: 100 → 0
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
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
    _setNavVisible(true);
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
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showNavigationChrome ||
        widget.showNavigationChrome != oldWidget.showNavigationChrome ||
        widget.navigationShell.currentIndex !=
            oldWidget.navigationShell.currentIndex) {
      _setNavVisible(true);
    }
  }

  void _setNavVisible(bool visible) {
    if (_navVisible == visible || !mounted) {
      return;
    }
    setState(() => _navVisible = visible);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.showNavigationChrome ||
        axisDirectionToAxis(notification.metrics.axisDirection) !=
            Axis.vertical) {
      return false;
    }

    // Always show nav when near the top of the scroll area.
    if (notification.metrics.pixels <=
        notification.metrics.minScrollExtent + CoolSpace.x8) {
      _setNavVisible(true);
      return false;
    }

    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.forward:
          _setNavVisible(true);
          break;
        case ScrollDirection.reverse:
          // Only hide after scrolling past a meaningful threshold to
          // prevent disorienting flicker on small swipes.
          if (notification.metrics.pixels > 200) {
            _setNavVisible(false);
          }
          break;
        case ScrollDirection.idle:
          break;
      }
    }

    return false;
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
    final safeAreaTop = MediaQuery.viewPaddingOf(context).top;
    final pillHeight = (62 + ((textScale - 1) * 10)).clamp(62, 74).toDouble();
    final isOffline = ref.watch(isOfflineProvider).valueOrNull ?? false;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: widget.navigationShell,
            ),
          ),
          // ── M3: Offline banner ─────────────────────────────────
          if (isOffline)
            Positioned(
              top: safeAreaTop,
              left: 0,
              right: 0,
              child: Material(
                color: colors.warning,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x4,
                    vertical: CoolSpace.x2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CoolIcons.warning,
                        size: 16,
                        color: colors.accentForeground,
                      ),
                      const SizedBox(width: CoolSpace.x2),
                      Expanded(
                        child: Text(
                          context.l10n.offlineBanner,
                          style: context.coolText
                              .mobiLabel(color: colors.accentForeground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.showNavigationChrome)
            Positioned(
              left: CoolSpace.x4,
              right: CoolSpace.x4,
              bottom: CoolSpace.x4 + safeAreaBottom,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: IgnorePointer(
                    ignoring: !_navVisible,
                    child: AnimatedSlide(
                      duration: CoolMotion.quick,
                      curve: Curves.easeOutCubic,
                      offset: _navVisible ? Offset.zero : const Offset(0, 1.25),
                      child: AnimatedOpacity(
                        duration: CoolMotion.quick,
                        curve: Curves.easeOutCubic,
                        opacity: _navVisible ? 1 : 0,
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
                                  icon: CoolIcons.homeRounded,
                                  isSelected: index == 0,
                                  onTap: () => _onItemTapped(0),
                                  colors: colors,
                                ),
                                _NavItem(
                                  label: context.l10n.navBiopay,
                                  icon: CoolIcons.faceScan,
                                  isSelected: index == 1,
                                  onTap: () => _onItemTapped(1),
                                  colors: colors,
                                ),
                                _NavItem(
                                  label: context.l10n.navProfile,
                                  icon: CoolIcons.settingsRounded,
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
        filter: ImageFilter.blur(
          sigmaX: CoolBlur.standard,
          sigmaY: CoolBlur.standard,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.overlaySurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(color: colors.border),
            boxShadow: CoolShadows.floating(null, strength: 0.8),
          ),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CoolSpace.x3,
                vertical: CoolSpace.x1,
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
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final activeColor = colors.primaryText;
    final inactiveColor = colors.secondaryText;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: CoolSpace.x3,
                  vertical: CoolSpace.x2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.03 : 1.0,
                  duration: CoolMotion.quick,
                  curve: CoolMotion.enterCurve,
                  child: Icon(
                    icon,
                    size: 19,
                    color: isSelected ? colors.accent : inactiveColor,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: CoolMotion.quick,
                style: context.coolText
                    .mobiLabel(color: isSelected ? activeColor : inactiveColor)
                    .copyWith(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                child: Text(
                  label,
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
