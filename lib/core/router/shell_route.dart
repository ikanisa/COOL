import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/mobility/providers/mobility_location_provider.dart';
import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../l10n/l10n.dart';
import '../theme/cool_palette.dart';

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

    final palette = context.coolPalette;
    final brightness = Theme.of(context).brightness;
    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navigationHeight = (84 + ((textScale - 1) * 26))
        .clamp(84, 108)
        .toDouble();
    final fabExtent = (60 + ((textScale - 1) * 10)).clamp(60, 70).toDouble();
    final navLabelFontSize = (12 + ((textScale - 1) * 1.5))
        .clamp(12, 14)
        .toDouble();

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
                  backgroundColor: palette.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: palette.surface.withValues(alpha: 0.75),
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 26,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: widget.showNavigationChrome
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.surface.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: palette.border.withValues(alpha: 0.8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: brightness == Brightness.light ? 0.08 : 0.26,
                          ),
                          blurRadius: 28,
                          spreadRadius: -12,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: navigationHeight,
                      child: BottomNavigationBar(
                        currentIndex: index,
                        onTap: _onItemTapped,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        type: BottomNavigationBarType.fixed,
                        selectedItemColor: palette.accent,
                        unselectedItemColor: palette.text3,
                        selectedFontSize: navLabelFontSize,
                        unselectedFontSize: navLabelFontSize,
                        selectedLabelStyle: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        unselectedLabelStyle: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
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
