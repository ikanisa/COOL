import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../brand/app_brand.dart';
import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../l10n/l10n.dart';
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

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex() {
    return widget.navigationShell.currentIndex;
  }

  void _onItemTapped(int index) {
    if (index == 2) {
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
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final brand = ref.watch(appBrandProvider);
    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;
    final navigationHeight = (78 + ((textScale - 1) * 18))
        .clamp(78, 96)
        .toDouble();
    final navLabelFontSize = (10 + ((textScale - 1) * 1.2))
        .clamp(10, 12)
        .toDouble();
    final navigationChromeInset = widget.showNavigationChrome
        ? navigationHeight + space.x5 + safeAreaBottom
        : 0.0;
    const navRadius = BorderRadius.all(Radius.circular(CoolRadii.xl));
    final navSelectedColor = brand.isRayonDominant
        ? Colors.white
        : colors.primaryText;
    final navUnselectedColor = colors.secondaryText.withValues(alpha: 0.88);
    final navSurfaceColor = brand.isRayonDominant
        ? Color.alphaBlend(
            brand.primaryColor.withValues(
              alpha: brightness == Brightness.dark ? 0.16 : 0.06,
            ),
            colors.overlaySurface.withValues(alpha: 0.88),
          )
        : colors.overlaySurface.withValues(alpha: 0.88);
    final navBorderColor = brand.isRayonDominant
        ? brand.secondaryColor.withValues(
            alpha: brightness == Brightness.dark ? 0.24 : 0.18,
          )
        : colors.border.withValues(alpha: 0.8);
    final homeLabel = brand.isRayonDominant
        ? context.l10n.rayon
        : context.l10n.navHome;
    final homeIcon = brand.isRayonDominant
        ? Icons.sports_soccer_rounded
        : Icons.home_rounded;

    return Scaffold(
      extendBody: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: navigationChromeInset),
        child: widget.navigationShell,
      ),
      bottomNavigationBar: widget.showNavigationChrome
          ? Padding(
              padding: EdgeInsets.fromLTRB(space.x5, 0, space.x5, space.x5),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: navRadius,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: CoolBlur.heavy,
                        sigmaY: CoolBlur.heavy,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: navSurfaceColor,
                          borderRadius: navRadius,
                          border: Border.all(color: navBorderColor),
                          boxShadow: CoolShadows.glass(
                            brightness,
                            strength: brightness == Brightness.light
                                ? 0.85
                                : 1.05,
                          ),
                        ),
                        child: SizedBox(
                          height: navigationHeight,
                          child: Row(
                            children: [
                              Expanded(
                                child: _ShellNavigationItem(
                                  label: homeLabel,
                                  icon: homeIcon,
                                  isSelected: index == 0,
                                  onTap: () => _onItemTapped(0),
                                  activeColor: navSelectedColor,
                                  inactiveColor: navUnselectedColor,
                                  activeBackground: brand.isRayonDominant
                                      ? brand.primaryColor
                                      : colors.accent,
                                  labelFontSize: navLabelFontSize,
                                ),
                              ),
                              Expanded(
                                child: _ShellNavigationItem(
                                  label: context.l10n.clubShop,
                                  icon: Icons.storefront_rounded,
                                  isSelected: index == 1,
                                  onTap: () => _onItemTapped(1),
                                  activeColor: navSelectedColor,
                                  inactiveColor: navUnselectedColor,
                                  activeBackground: colors.highlightColor,
                                  labelFontSize: navLabelFontSize,
                                  selectedForegroundOverride:
                                      colors.appBackground,
                                ),
                              ),
                              Expanded(
                                child: _ShellNavigationItem(
                                  label: context.l10n.momoScreenTitle,
                                  icon: Icons.account_balance_wallet_rounded,
                                  isSelected: index == 2,
                                  onTap: () => _onItemTapped(2),
                                  activeColor: navSelectedColor,
                                  inactiveColor: navUnselectedColor,
                                  activeBackground: brand.isRayonDominant
                                      ? brand.secondaryColor
                                      : colors.highlightColor,
                                  labelFontSize: navLabelFontSize,
                                  selectedForegroundOverride:
                                      brand.isRayonDominant
                                      ? colors.appBackground
                                      : colors.appBackground,
                                ),
                              ),
                              Expanded(
                                child: _ShellNavigationItem(
                                  label: 'Services',
                                  icon: Icons.grid_view_rounded,
                                  isSelected: index == 3,
                                  onTap: () => _onItemTapped(3),
                                  activeColor: navSelectedColor,
                                  inactiveColor: navUnselectedColor,
                                  activeBackground: colors.accentStrong,
                                  labelFontSize: navLabelFontSize,
                                ),
                              ),
                              Expanded(
                                child: _ShellNavigationItem(
                                  label: context.l10n.navProfile,
                                  icon: Icons.person_rounded,
                                  isSelected: index == 4,
                                  onTap: () => _onItemTapped(4),
                                  activeColor: navSelectedColor,
                                  inactiveColor: navUnselectedColor,
                                  activeBackground: colors.highlightColor,
                                  labelFontSize: navLabelFontSize,
                                  selectedForegroundOverride:
                                      colors.appBackground,
                                ),
                              ),
                            ],
                          ),
                        ),
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

class _ShellNavigationItem extends StatelessWidget {
  const _ShellNavigationItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
    required this.activeBackground,
    required this.labelFontSize,
    this.selectedForegroundOverride,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;
  final Color activeBackground;
  final double labelFontSize;
  final Color? selectedForegroundOverride;

  @override
  Widget build(BuildContext context) {
    final selectedForeground = selectedForegroundOverride ?? activeColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            decoration: BoxDecoration(
              color: isSelected ? activeBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? selectedForeground : inactiveColor,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText
                      .mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? selectedForeground : inactiveColor,
                        letterSpacing: 0.8,
                      )
                      .copyWith(fontSize: labelFontSize),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
