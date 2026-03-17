import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/driver_card.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../models/driver_info.dart';
import '../providers/discovery_provider.dart';
import '../providers/mobility_location_provider.dart';

import '../providers/vehicle_type_provider.dart';

final _fallbackVehicleFilters = [
  const MobilityVehicleFilter(label: 'All', value: 'All'),
  const MobilityVehicleFilter(label: 'Moto', value: 'Moto'),
  const MobilityVehicleFilter(label: 'Cab', value: 'Cab'),
  const MobilityVehicleFilter(label: 'Truck', value: 'Truck'),
  const MobilityVehicleFilter(label: 'Trike', value: 'Trike'),
  const MobilityVehicleFilter(label: 'Others', value: 'Others'),
];

final mobilityVehicleFiltersProvider = Provider<List<MobilityVehicleFilter>>((
  ref,
) {
  final typesAsync = ref.watch(currentCountryVehicleTypesProvider);
  return typesAsync.when(
    data: (types) => types
        .map(
          (type) => MobilityVehicleFilter(label: type.label, value: type.value),
        )
        .toList(growable: false),
    loading: () => _fallbackVehicleFilters,
    error: (_, _) => _fallbackVehicleFilters,
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// VEHICLE FILTER DATA MODEL
// ═════════════════════════════════════════════════════════════════════════════

/// Simple label/value pair for vehicle type filter chips.
class MobilityVehicleFilter {
  const MobilityVehicleFilter({required this.label, required this.value});

  final String label;
  final String value;
}

// ═════════════════════════════════════════════════════════════════════════════
// TOP ACTIONS CARD
// ═════════════════════════════════════════════════════════════════════════════

class MobilityTopActionsCard extends ConsumerStatefulWidget {
  const MobilityTopActionsCard({
    required this.isDriver,
    required this.onScheduleTrip,
    super.key,
  });

  final bool isDriver;
  final VoidCallback onScheduleTrip;

  @override
  ConsumerState<MobilityTopActionsCard> createState() =>
      _MobilityTopActionsCardState();
}

class _MobilityTopActionsCardState
    extends ConsumerState<MobilityTopActionsCard> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // Current UI maps to a legacy 0/1/2 index for tabs.
    // 0 = Discovery (Nearby), 1 = Scheduled Trips, 2 = Schedule Trip Action
    // We maintain this index in DiscoveryNotifier for UI consistency.
    final activeTab = ref.watch(discoveryProvider.select((s) => s.selectedTab));

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MobilityTabBar(
            activeIndex: activeTab,
            onChanged: (index) {
              if (index == 2) {
                widget.onScheduleTrip();
                return;
              }
              final notifier = ref.read(discoveryProvider.notifier);
              notifier.setSelectedTab(index);
              if (index == 0) {
                unawaited(notifier.loadNearbyDrivers());
              } else {
                unawaited(notifier.loadNearbyTrips());
              }
            },
          ),
          const SizedBox(height: 12),
          const MobilityFilterBar(),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER BAR
// ═════════════════════════════════════════════════════════════════════════════

class MobilityFilterBar extends ConsumerWidget {
  const MobilityFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVehicle = ref.watch(discoveryProvider.select((s) => s.selectedVehicle));
    final filters = ref.watch(mobilityVehicleFiltersProvider);
    final notifier = ref.read(discoveryProvider.notifier);
    final chips = [
      for (final filter in filters)
        VehicleChip(
          label: filter.label,
          isSelected: selectedVehicle == filter.value,
          onTap: () {
            unawaited(notifier.setVehicleFilter(filter.value));
          },
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Wrap(spacing: 8, runSpacing: 8, children: chips);
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 18),
          child: Row(
            children: [
              for (var index = 0; index < chips.length; index++) ...[
                chips[index],
                if (index != chips.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3-TAB BAR (Nearby Drivers | Trips | Schedule trip)
// ═════════════════════════════════════════════════════════════════════════════

class _MobilityTabBar extends StatelessWidget {
  const _MobilityTabBar({
    required this.activeIndex,
    required this.onChanged,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    const tabs = [
      (icon: Icons.people_outline_rounded, label: 'Nearby'),
      (icon: Icons.route_rounded, label: 'Trips'),
      (icon: Icons.add_circle_outline_rounded, label: 'Schedule'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: activeIndex == i,
                label: '${tabs[i].label} tab',
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: activeIndex == i
                          ? AppColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tabs[i].icon,
                          size: 18,
                          color: activeIndex == i
                              ? onPrimary
                              : AppColors.text2,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tabs[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: activeIndex == i ? FontWeight.w800 : FontWeight.w600,
                              color: activeIndex == i ? onPrimary : AppColors.text2,
                            ),
                          ),
                        ),
                      ],
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

// ═════════════════════════════════════════════════════════════════════════════
// CONTENT SLIVER (dispatches to drivers or trips)
// ═════════════════════════════════════════════════════════════════════════════

class MobilityContentSliver extends ConsumerWidget {
  const MobilityContentSliver({
    required this.onDriverPreviewTap,
    required this.onDriverWhatsAppTap,
    required this.onTripPreviewTap,
    super.key,
  });

  final ValueChanged<DriverInfo> onDriverPreviewTap;
  final ValueChanged<DriverInfo> onDriverWhatsAppTap;
  final ValueChanged<Trip> onTripPreviewTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryState = ref.watch(discoveryProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final isLoading = discoveryState.isLoading;
    final error = discoveryState.error;
    final drivers = discoveryState.nearbyDrivers;
    final trips = discoveryState.nearbyTrips;

    // We determine "tab" based on state for now (Drivers view is primary)
    final isTripsView = discoveryState.selectedTab == 1;

    if (isTripsView) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _buildTripSliver(
          locationState: locationState,
          isLoading: isLoading,
          error: error,
          trips: trips,
          onTripPreviewTap: onTripPreviewTap,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      sliver: _buildDriverSliver(
        ref,
        locationState: locationState,
        isLoading: isLoading,
        error: error,
        drivers: drivers,
      ),
    );
  }

  Widget _buildDriverSliver(
    WidgetRef ref, {
    required MobilityLocationState locationState,
    required bool isLoading,
    required String? error,
    required List<DriverInfo> drivers,
  }) {
    if (isLoading && drivers.isEmpty && locationState.hasLocation) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CoolSkeletonList(itemCount: 2),
        ),
      );
    }

    if (error != null && drivers.isEmpty && locationState.hasLocation) {
      return _MobilityStatusSliver(message: error, color: AppColors.red);
    }

    return MobilityNearbyDriversSliver(
      drivers: drivers,
      selectedVehicle: ref.watch(discoveryProvider.select((s) => s.selectedVehicle)),
      onPreviewTap: onDriverPreviewTap,
      onWhatsAppTap: onDriverWhatsAppTap,
    );
  }

  Widget _buildTripSliver({
    required MobilityLocationState locationState,
    required bool isLoading,
    required String? error,
    required List<Trip> trips,
    required ValueChanged<Trip> onTripPreviewTap,
  }) {
    if (isLoading && trips.isEmpty && locationState.hasLocation) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CoolSkeletonList(itemCount: 2),
        ),
      );
    }

    if (error != null && trips.isEmpty && locationState.hasLocation) {
      return _MobilityStatusSliver(message: error, color: AppColors.red);
    }

    return MobilityScheduledTripsSliver(
      trips: trips,
      onPreviewTap: onTripPreviewTap,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NEARBY DRIVERS SLIVER
// ═════════════════════════════════════════════════════════════════════════════

class MobilityNearbyDriversSliver extends StatelessWidget {
  const MobilityNearbyDriversSliver({
    required this.drivers,
    required this.selectedVehicle,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    super.key,
  });

  final List<DriverInfo> drivers;
  final String selectedVehicle;
  final ValueChanged<DriverInfo> onPreviewTap;
  final ValueChanged<DriverInfo> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      final message = selectedVehicle == 'All'
          ? 'No nearby drivers found.'
          : 'No nearby drivers found for ${selectedVehicle.toLowerCase()}.';
      return _MobilityStatusSliver(message: message);
    }

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final driver = drivers[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == drivers.length - 1 ? 0 : 12,
              ),
              child: DriverCard(
                driverId: driver.driverId,
                displayName: driver.displayName,
                vehicleType: driver.vehicleType,
                distanceKm: driver.distanceKm,
                isOnline: driver.isOnline,
                onTap: () => onPreviewTap(driver),
                onWhatsAppTap: () => onWhatsAppTap(driver),
              ),
            );
          }, childCount: drivers.length),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SCHEDULED TRIPS SLIVER
// ═════════════════════════════════════════════════════════════════════════════

class MobilityScheduledTripsSliver extends StatelessWidget {
  const MobilityScheduledTripsSliver({
    required this.trips,
    required this.onPreviewTap,
    super.key,
  });

  final List<Trip> trips;
  final ValueChanged<Trip> onPreviewTap;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return _MobilityStatusSliver(message: 'No scheduled trips found');
    }

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final trip = trips[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TripCard(
                fromLocation: trip.fromLocation,
                toLocation: trip.toLocation,
                departureTime: trip.departureTime,
                vehicleType: trip.vehicleType,
                onTap: () => onPreviewTap(trip),
                seats: trip.seats,
                isReturn: trip.isReturn,
                isRecurring: trip.isRecurring,
                isDriverReturnTrip: trip.isDriverReturnTrip,
              ),
            );
          }, childCount: trips.length),
        ),
      ],
    );
  }
}

class _MobilityStatusSliver extends StatelessWidget {
  _MobilityStatusSliver({required this.message, Color? color})
    : color = color ?? AppColors.text2;

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}