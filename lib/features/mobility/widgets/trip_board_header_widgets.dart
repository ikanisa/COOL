import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../providers/trip_board_provider.dart';

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
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CoolButton(label: primaryLabel, onTap: onPrimaryTap),
          ),
          if (child != null) ...[
            const SizedBox(height: 16),
            child!,
          ],
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
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final title = activeTab == TripBoardTab.driverReturnTrips
        ? 'Driver return trips'
        : 'Explore trips';
    final subtitle = activeTab == TripBoardTab.driverReturnTrips
        ? 'Browse return routes from drivers heading back.'
        : 'Find a nearby ride, then continue on WhatsApp if it fits.';

    return TripBoardHeaderCard(
      title: title,
      subtitle: subtitle,
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TripBoardTabSection(),
          SizedBox(height: 12),
          TripBoardFilterBar(),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activeView == item.$1
                        ? AppColors.accent
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
                          ? Colors.black
                          : AppColors.text2,
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
    (TripBoardTab.driverReturnTrips, 'Return trips'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activeTab == tab.$1
                        ? AppColors.accent
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
                          ? Colors.black
                          : AppColors.text2,
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
          for (var index = 0; index < tripBoardVehicleFilters.length; index++) ...[
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
