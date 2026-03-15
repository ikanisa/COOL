import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../providers/trip_board_provider.dart';
import 'trip_display_strings.dart';

/// Vehicle filter model.
class VehicleFilter {
  const VehicleFilter({required this.label, required this.value});

  final String label;
  final String value;
}

/// Default vehicle filters used on the trip board.
const tripBoardVehicleFilters = [
  VehicleFilter(label: 'All', value: 'All'),
  VehicleFilter(label: 'Moto', value: 'Moto'),
  VehicleFilter(label: 'Cab', value: 'Cab'),
  VehicleFilter(label: 'Truck', value: 'Truck'),
  VehicleFilter(label: 'Liffan', value: 'Liffan'),
];

/// View mode for the trip board tabs.
enum TripBoardViewMode { explore, myTrips }

/// Reusable header card with title, subtitle, primary button, and optional child.
class TripBoardHeaderCard extends StatelessWidget {
  const TripBoardHeaderCard({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CoolButton(label: primaryLabel, onTap: onPrimaryTap),
          ),
          if (child != null) ...[const SizedBox(height: 16), child!],
        ],
      ),
    );
  }
}

/// Explore tab header card with tab switcher and filter bar.
class TripBoardExploreHeaderCard extends ConsumerWidget {
  const TripBoardExploreHeaderCard({required this.onPostTrip, super.key});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TripBoardHeaderCard(
      title: 'Explore trips',
      subtitle: 'Find a nearby ride, then continue on WhatsApp if it fits.',
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
    );
  }
}

class TripBoardExploreControlsCard extends ConsumerWidget {
  const TripBoardExploreControlsCard({
    required this.onOpenTripType,
    required this.onOpenVehicleFilter,
    super.key,
  });

  final VoidCallback onOpenTripType;
  final VoidCallback onOpenVehicleFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final selectedVehicle = ref.watch(tripBoardSelectedVehicleProvider);
    final palette = context.coolPalette;

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${tripBoardTabLabel(activeTab)} · ${tripBoardVehicleSummary(selectedVehicle)}',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Trip type',
                  onTap: onOpenTripType,
                  variant: CoolButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: 'Filters',
                  onTap: onOpenVehicleFilter,
                  variant: CoolButtonVariant.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// My-trips tab header card.
class TripBoardMyTripsHeaderCard extends StatelessWidget {
  const TripBoardMyTripsHeaderCard({required this.onPostTrip, super.key});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context) {
    return TripBoardHeaderCard(
      title: 'Manage your trips',
      subtitle: 'Pause, repost, or delete what you already posted.',
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
    );
  }
}

/// Explore / My trips mode switcher.
class TripBoardModeSwitcher extends StatelessWidget {
  const TripBoardModeSwitcher({
    required this.activeView,
    required this.onChanged,
    super.key,
  });

  final TripBoardViewMode activeView;
  final ValueChanged<TripBoardViewMode> onChanged;

  static const _items = [
    (TripBoardViewMode.explore, 'Explore'),
    (TripBoardViewMode.myTrips, 'My trips'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: Semantics(
                button: true,
                selected: activeView == item.$1,
                label: '${item.$2} tab',
                child: GestureDetector(
                  onTap: () => onChanged(item.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: activeView == item.$1
                          ? palette.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: activeView == item.$1
                            ? Theme.of(context).colorScheme.onPrimary
                            : palette.text2,
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

/// Passenger / Return trips tab switcher.
class TripBoardTabSwitcher extends StatelessWidget {
  const TripBoardTabSwitcher({
    required this.activeTab,
    required this.onChanged,
    super.key,
  });

  final TripBoardTab activeTab;
  final ValueChanged<TripBoardTab> onChanged;

  static const _tabs = [
    (TripBoardTab.passengerTrips, 'Passenger'),
    (TripBoardTab.driverReturnTrips, 'Driver returns'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: Semantics(
                button: true,
                selected: activeTab == tab.$1,
                label: '${tab.$2} tab',
                child: GestureDetector(
                  onTap: () => onChanged(tab.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: activeTab == tab.$1
                          ? palette.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tab.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: activeTab == tab.$1
                            ? Theme.of(context).colorScheme.onPrimary
                            : palette.text2,
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

/// Tab section wired to the provider.
class TripBoardTabSection extends ConsumerWidget {
  const TripBoardTabSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    return TripBoardTabSwitcher(
      activeTab: activeTab,
      onChanged: (tab) {
        unawaited(ref.read(tripBoardProvider.notifier).setActiveTab(tab));
      },
    );
  }
}

/// Vehicle-type filter bar.
class TripBoardFilterBar extends ConsumerWidget {
  const TripBoardFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVehicle = ref.watch(tripBoardSelectedVehicleProvider);
    final notifier = ref.read(tripBoardProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (
            var index = 0;
            index < tripBoardVehicleFilters.length;
            index++
          ) ...[
            VehicleChip(
              label: tripBoardVehicleFilters[index].label,
              isSelected:
                  selectedVehicle == tripBoardVehicleFilters[index].value,
              onTap: () {
                unawaited(
                  notifier.setVehicleFilter(
                    tripBoardVehicleFilters[index].value,
                  ),
                );
              },
            ),
            if (index != tripBoardVehicleFilters.length - 1)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

String tripBoardTabLabel(TripBoardTab tab) {
  return tripCollectionLabel(
    isDriverReturn: tab == TripBoardTab.driverReturnTrips,
  );
}

String tripBoardVehicleSummary(String selectedVehicle) {
  return selectedVehicle == 'All'
      ? 'All vehicle types'
      : '$selectedVehicle only';
}

class TripBoardTripTypeSheet extends StatelessWidget {
  const TripBoardTripTypeSheet({required this.activeTab, super.key});

  final TripBoardTab activeTab;

  @override
  Widget build(BuildContext context) {
    return _TripBoardSelectionSheet<TripBoardTab>(
      title: 'Trip type',
      subtitle: 'Choose which type of trip to show first.',
      value: activeTab,
      options: const <({TripBoardTab value, String label, String subtitle})>[
        (
          value: TripBoardTab.passengerTrips,
          label: 'Passenger trips',
          subtitle: 'Regular rides near your current location.',
        ),
        (
          value: TripBoardTab.driverReturnTrips,
          label: 'Driver returns',
          subtitle: 'Drivers heading back with seats available.',
        ),
      ],
    );
  }
}

class TripBoardVehicleFilterSheet extends StatelessWidget {
  const TripBoardVehicleFilterSheet({required this.selectedVehicle, super.key});

  final String selectedVehicle;

  @override
  Widget build(BuildContext context) {
    return _TripBoardSelectionSheet<String>(
      title: 'Vehicle filter',
      subtitle: 'Keep vehicle filtering secondary unless you need it.',
      value: selectedVehicle,
      options: [
        for (final filter in tripBoardVehicleFilters)
          (
            value: filter.value,
            label: filter.label,
            subtitle: filter.value == 'All'
                ? 'Show every available vehicle type.'
                : 'Only show ${filter.label.toLowerCase()} trips.',
          ),
      ],
    );
  }
}

class _TripBoardSelectionSheet<T> extends StatelessWidget {
  const _TripBoardSelectionSheet({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
  });

  final String title;
  final String subtitle;
  final T value;
  final List<({T value, String label, String subtitle})> options;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              for (var index = 0; index < options.length; index++) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    options[index].value == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: options[index].value == value
                        ? palette.accent
                        : palette.text3,
                  ),
                  title: Text(
                    options[index].label,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  subtitle: Text(
                    options[index].subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: palette.text2,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(options[index].value),
                ),
                if (index != options.length - 1) Divider(color: palette.border),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
