import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/widgets/momo_sms_rationale_sheet.dart';
import '../../features/mobility/providers/mobility_location_provider.dart';
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


    final index = _currentIndex();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final navigationHeight = (76 + ((textScale - 1) * 24))
        .clamp(76, 98)
        .toDouble();
    final fabExtent = (54 + ((textScale - 1) * 8)).clamp(54, 62).toDouble();
    final navLabelFontSize = (10 + ((textScale - 1) * 1.5))
        .clamp(10, 12)
        .toDouble();
    _syncMobilityBranchVisibility(widget.navigationShell.currentIndex == 2);

    return Scaffold(
      extendBody: true, // Allow content to flow behind the glass bar
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
                  elevation: 8,
                  backgroundColor: palette.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: palette.border2, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFF8885F0),
                    size: 24,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ── Bottom nav ───────────────────────────────────────────────
      bottomNavigationBar: widget.showNavigationChrome
          ? ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: 0.7),
                    border: Border(
                      top: BorderSide(
                        color: palette.border.withValues(alpha: 0.3),
                      ),
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
                      selectedItemColor: palette.accent,
                      unselectedItemColor: palette.text3,
                      selectedFontSize: navLabelFontSize,
                      unselectedFontSize: navLabelFontSize,
                      selectedLabelStyle: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      unselectedLabelStyle: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w500,
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
            )
          : null,
    );
  }
}
