import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/mobility/providers/mobility_location_provider.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// The main scaffold that wraps all bottom-nav routes.
///
/// Provides a 5-slot [BottomNavigationBar] (Home, Groups, _FAB_, Mobility,
/// Profile) with a centre floating action button that navigates to the
/// Mobile Money hub screen.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // ── Navigation index mapping ────────────────────────────────────────

  static const _navToBranch = <int, int>{0: 0, 1: 1, 3: 2, 4: 3};
  bool? _lastMobilityActive;

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
      ref
          .read(mobilityLocationProvider.notifier)
          .setMobilityBranchActive(isActive);
    });
  }

  @override
  void dispose() {
    ref.read(mobilityLocationProvider.notifier).setMobilityBranchActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex();
    _syncMobilityBranchVisibility(widget.navigationShell.currentIndex == 2);

    return Scaffold(
      body: widget.navigationShell,

      // ── FAB ──────────────────────────────────────────────────────
      floatingActionButton: SizedBox(
        width: 56,
        height: 56,
        child: FloatingActionButton(
          onPressed: _onFabPressed,
          elevation: 0,
          backgroundColor: AppColors.accent,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ── Bottom nav ───────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: SizedBox(
          height: 76,
          child: BottomNavigationBar(
            currentIndex: index,
            onTap: _onItemTapped,
            backgroundColor: AppColors.surface,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.accent,
            unselectedItemColor: AppColors.text3,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w500),
            unselectedLabelStyle: GoogleFonts.dmSans(
              fontWeight: FontWeight.w400,
            ),
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_rounded),
                label: context.l10n.navHome,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.people_rounded),
                label: context.l10n.navGroups,
              ),
              BottomNavigationBarItem(
                icon: const ExcludeSemantics(child: SizedBox.shrink()),
                label: context.l10n.sendAction,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.directions_car_rounded),
                label: context.l10n.navMobility,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person_rounded),
                label: context.l10n.navProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
