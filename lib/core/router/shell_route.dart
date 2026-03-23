import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/mobility/providers/mobility_location_provider.dart';
import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../../shared/widgets/cool_card.dart';
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
  static const _navToBranch = <int, int>{0: 0, 1: 1, 3: 2, 4: 3};

  late final MobilityLocationNotifier _mobilityLocationNotifier;
  bool? _lastMobilityActive;

  @override
  void initState() {
    super.initState();
    _mobilityLocationNotifier = ref.read(mobilityLocationProvider.notifier);
  }

  int _currentIndex() {
    return switch (widget.navigationShell.currentIndex) {
      0 => 0,
      1 => 1,
      2 => 3,
      3 => 4,
      _ => 0,
    };
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      _onFabPressed();
      return;
    }

    HapticFeedback.selectionClick();
    final branchIndex = _navToBranch[index];
    if (branchIndex == null) {
      return;
    }

    widget.navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == widget.navigationShell.currentIndex,
    );
  }

  void _onFabPressed() {
    HapticFeedback.mediumImpact();
    context.push('/momo');
  }

  void _syncMobilityBranchVisibility(bool isActive) {
    if (_lastMobilityActive == isActive) {
      return;
    }

    _lastMobilityActive = isActive;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _mobilityLocationNotifier.setMobilityBranchActive(isActive);
    });
  }

  @override
  void dispose() {
    _mobilityLocationNotifier.setMobilityBranchActive(false);
    super.dispose();
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
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navigationHeight = (84 + ((textScale - 1) * 26))
        .clamp(84, 108)
        .toDouble();
    final fabExtent = (60 + ((textScale - 1) * 10)).clamp(60, 70).toDouble();
    final navLabelFontSize = (12 + ((textScale - 1) * 1.5))
        .clamp(12, 14)
        .toDouble();
    const navRadius = BorderRadius.all(Radius.circular(CoolRadii.xl));
    const fabRadius = BorderRadius.all(Radius.circular(CoolRadii.lg));

    _syncMobilityBranchVisibility(widget.navigationShell.currentIndex == 2);

    return Scaffold(
      extendBody: true,
      body: widget.navigationShell,
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
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: fabRadius,
                    side: BorderSide(
                      color: colors.elevatedBackground.withValues(alpha: 0.75),
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
                      color: colors.overlaySurface.withValues(alpha: 0.82),
                      borderRadius: navRadius,
                      border: Border.all(
                        color: colors.border.withValues(alpha: 0.8),
                      ),
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
                        selectedItemColor: colors.accent,
                        unselectedItemColor: colors.tertiaryText,
                        selectedFontSize: navLabelFontSize,
                        unselectedFontSize: navLabelFontSize,
                        selectedLabelStyle: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                        unselectedLabelStyle: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        items: [
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: '${context.l10n.navHome} tab',
                              selected: index == 0,
                              child: const Icon(Icons.home_rounded),
                            ),
                            label: context.l10n.navHome,
                          ),
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: '${context.l10n.navGroups} tab',
                              selected: index == 1,
                              child: const Icon(Icons.people_rounded),
                            ),
                            label: context.l10n.navGroups,
                          ),
                          const BottomNavigationBarItem(
                            icon: SizedBox.shrink(),
                            label: '',
                          ),
                          BottomNavigationBarItem(
                            icon: Semantics(
                              label: '${context.l10n.navMobility} tab',
                              selected: index == 3,
                              child: const Icon(Icons.directions_car_rounded),
                            ),
                            label: context.l10n.navMobility,
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
