import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/mobility/providers/mobility_location_provider.dart';
import '../l10n/l10n.dart';
import '../theme/cool_palette.dart';

/// The main scaffold that wraps all bottom-nav routes.
///
/// Provides a 5-slot [BottomNavigationBar] (Home, Groups, _FAB_, Mobility,
/// Profile) with a centre floating action button that navigates to the
/// Mobile Money hub screen.
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
  // ── Navigation index mapping ────────────────────────────────────────

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
    final palette = context.coolPalette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navigationHeight = (72 + ((textScale - 1) * 24))
        .clamp(72, 96)
        .toDouble();
    final fabExtent = (54 + ((textScale - 1) * 8)).clamp(54, 62).toDouble();
    final navLabelFontSize = (10 + ((textScale - 1) * 1.5))
        .clamp(10, 12)
        .toDouble();
    _syncMobilityBranchVisibility(widget.navigationShell.currentIndex == 2);

    return Scaffold(
      body: widget.navigationShell,

      // ── FAB ──────────────────────────────────────────────────────
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
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: palette.border2),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: onPrimary,
                    size: 24,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ── Bottom nav ───────────────────────────────────────────────
      bottomNavigationBar: widget.showNavigationChrome
          ? Container(
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.border)),
                boxShadow: [
                  BoxShadow(
                    color: palette.text.withValues(
                      alpha: Theme.of(context).brightness == Brightness.light
                          ? 0.06
                          : 0.18,
                    ),
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: SizedBox(
                height: navigationHeight,
                child: BottomNavigationBar(
                  currentIndex: index,
                  onTap: _onItemTapped,
                  backgroundColor: palette.surface,
                  elevation: 0,
                  type: BottomNavigationBarType.fixed,
                  selectedItemColor: palette.accent,
                  unselectedItemColor: palette.text3,
                  selectedFontSize: navLabelFontSize,
                  unselectedFontSize: navLabelFontSize,
                  selectedLabelStyle: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w400,
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
                    BottomNavigationBarItem(
                      icon: Semantics(
                        label: context.l10n.momoScreenTitle,
                        child: ExcludeSemantics(child: SizedBox.shrink()),
                      ),
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
            )
          : null,
    );
  }
}
