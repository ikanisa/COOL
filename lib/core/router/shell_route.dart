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

  void _onFabPressed() {
    _onItemTapped(2);
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
    final navigationHeight = (84 + ((textScale - 1) * 26))
        .clamp(84, 108)
        .toDouble();
    final fabExtent = (60 + ((textScale - 1) * 10)).clamp(60, 70).toDouble();
    final navLabelFontSize = (12 + ((textScale - 1) * 1.5))
        .clamp(12, 14)
        .toDouble();
    final navigationChromeInset = widget.showNavigationChrome
        ? navigationHeight + space.x5 + safeAreaBottom + (fabExtent / 2)
        : 0.0;
    const navRadius = BorderRadius.all(Radius.circular(CoolRadii.xl));
    const fabRadius = BorderRadius.all(Radius.circular(CoolRadii.lg));
    final navSelectedColor = brand.isRayonDominant
        ? brand.navSelectedColor
        : colors.accent;
    final navUnselectedColor = brand.isRayonDominant
        ? colors.secondaryText.withValues(alpha: 0.92)
        : colors.tertiaryText;
    final navSurfaceColor = brand.isRayonDominant
        ? Color.alphaBlend(
            brand.primaryColor.withValues(
              alpha: brightness == Brightness.dark ? 0.26 : 0.10,
            ),
            colors.overlaySurface.withValues(alpha: 0.9),
          )
        : colors.overlaySurface.withValues(alpha: 0.82);
    final navBorderColor = brand.isRayonDominant
        ? brand.secondaryColor.withValues(
            alpha: brightness == Brightness.dark ? 0.34 : 0.22,
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
      floatingActionButton: widget.showNavigationChrome
          ? Semantics(
              button: true,
              label: context.l10n.momoScreenTitle,
              child: SizedBox(
                width: fabExtent,
                height: fabExtent,
                child: FloatingActionButton(
                  onPressed: _onFabPressed,
                  tooltip: context.l10n.momoScreenTitle,
                  elevation: 0,
                  backgroundColor: brand.isRayonDominant
                      ? brand.primaryColor
                      : colors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: fabRadius,
                    side: BorderSide(
                      color: brand.isRayonDominant
                          ? brand.secondaryColor.withValues(alpha: 0.55)
                          : colors.elevatedBackground.withValues(alpha: 0.75),
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: colors.accentForeground,
                    size: 26,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: widget.showNavigationChrome
          ? Padding(
              padding: EdgeInsets.fromLTRB(space.x5, 0, space.x5, space.x5),
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
                        strength: brightness == Brightness.light ? 0.85 : 1.05,
                      ),
                    ),
                    child: SizedBox(
                      height: navigationHeight,
                      child: BottomNavigationBar(
                        currentIndex: index,
                        onTap: _onItemTapped,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        type: BottomNavigationBarType.fixed,
                        selectedItemColor: navSelectedColor,
                        unselectedItemColor: navUnselectedColor,
                        selectedFontSize: navLabelFontSize,
                        unselectedFontSize: navLabelFontSize,
                        selectedLabelStyle: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                        unselectedLabelStyle: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        items: [
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: '$homeLabel tab',
                              selected: index == 0,
                              child: Icon(homeIcon),
                            ),
                            label: homeLabel,
                          ),
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: 'Shop tab',
                              selected: index == 1,
                              child: const Icon(Icons.storefront_rounded),
                            ),
                            label: context.l10n.clubShop,
                          ),
                          const BottomNavigationBarItem(
                            icon: SizedBox.shrink(),
                            label: '',
                          ),
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: 'Services tab',
                              selected: index == 3,
                              child: const Icon(Icons.grid_view_rounded),
                            ),
                            label: 'Services',
                          ),
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: '${context.l10n.navProfile} tab',
                              selected: index == 4,
                              child: const Icon(Icons.person_rounded),
                            ),
                            label: context.l10n.navProfile,
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
