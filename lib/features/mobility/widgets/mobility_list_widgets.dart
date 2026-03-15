import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/driver_card.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../models/driver_info.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../providers/vehicle_type_provider.dart';

const _fallbackVehicleFilters = [
  MobilityVehicleFilter(label: 'All', value: 'All'),
  MobilityVehicleFilter(label: 'Moto', value: 'Moto'),
  MobilityVehicleFilter(label: 'Cab', value: 'Cab'),
  MobilityVehicleFilter(label: 'Truck', value: 'Truck'),
  MobilityVehicleFilter(label: 'Liffan', value: 'Liffan'),
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

class MobilityTopActionsCard extends StatelessWidget {
  const MobilityTopActionsCard({
    required this.isDriver,
    required this.onOpenTrips,
    required this.onScheduleTrip,
    this.onOpenDriverTools,
    super.key,
  });

  final bool isDriver;
  final VoidCallback onOpenTrips;
  final VoidCallback onScheduleTrip;
  final VoidCallback? onOpenDriverTools;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find or post a ride',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDriver
                ? 'Start with one trip action. Driver mode stays available, but it no longer competes with browsing.'
                : 'Start with one trip action. Driver setup stays out of the way until you need it.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Schedule trip',
                  onTap: onScheduleTrip,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: 'Trip board',
                  variant: CoolButtonVariant.secondary,
                  onTap: onOpenTrips,
                ),
              ),
            ],
          ),
          if (isDriver && onOpenDriverTools != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenDriverTools,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Manage driver mode'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BROWSE CONTROLS
// ═════════════════════════════════════════════════════════════════════════════

class MobilityBrowseControlsCard extends ConsumerWidget {
  const MobilityBrowseControlsCard({
    required this.supportsEmbeddedMaps,
    required this.showMap,
    required this.onToggleMap,
    super.key,
  });

  final bool supportsEmbeddedMaps;
  final bool showMap;
  final VoidCallback onToggleMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(mobilityActiveTabProvider);
    final selectedVehicle = ref.watch(mobilitySelectedVehicleProvider);
    final title = activeTab == 0 ? 'Nearby drivers' : 'Scheduled trips';
    final subtitle = activeTab == 0
        ? 'Keep the list simple. Open filters only when you need a specific vehicle type.'
        : 'Browse upcoming posted trips near you.';
    final statusLabel = activeTab == 0
        ? selectedVehicle == 'All'
              ? 'All vehicle types'
              : 'Filtered by $selectedVehicle'
        : 'Trips near your location';

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 14,
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
          const MobilityTabSection(),
          const SizedBox(height: 12),
          Text(
            statusLabel,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
            ),
          ),
          if (activeTab == 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const MobilityFilterSheet(),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.surface2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                if (supportsEmbeddedMaps)
                  OutlinedButton.icon(
                    onPressed: onToggleMap,
                    icon: Icon(
                      showMap ? Icons.map_rounded : Icons.map_outlined,
                      size: 18,
                    ),
                    label: Text(showMap ? 'Hide map' : 'Show map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(color: AppColors.border),
                      backgroundColor: AppColors.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MobilityFilterSheet extends ConsumerWidget {
  const MobilityFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVehicle = ref.watch(mobilitySelectedVehicleProvider);
    final filters = ref.watch(mobilityVehicleFiltersProvider);
    final notifier = ref.read(mobilityProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vehicle filter',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              Text(
                'Pick one type only when you want to narrow nearby drivers.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in filters)
                    VehicleChip(
                      label: filter.label,
                      isSelected: selectedVehicle == filter.value,
                      onTap: () {
                        unawaited(notifier.setVehicleFilter(filter.value));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Reset',
                      variant: CoolButtonVariant.secondary,
                      onTap: () {
                        unawaited(notifier.setVehicleFilter('All'));
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CoolButton(
                      label: 'Done',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MAP TOGGLE CARD
// ═════════════════════════════════════════════════════════════════════════════

class MobilityMapToggleCard extends StatelessWidget {
  const MobilityMapToggleCard({
    required this.isExpanded,
    required this.onTap,
    super.key,
  });

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.map_outlined, size: 20, color: AppColors.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby map',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isExpanded ? 'Tap to hide.' : 'Tap to show.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(isExpanded ? 'Hide' : 'Show'),
          ),
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
    final selectedVehicle = ref.watch(mobilitySelectedVehicleProvider);
    final filters = ref.watch(mobilityVehicleFiltersProvider);
    final notifier = ref.read(mobilityProvider.notifier);
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
// TAB SECTION + DUAL TAB SWITCHER
// ═════════════════════════════════════════════════════════════════════════════

class MobilityTabSection extends ConsumerWidget {
  const MobilityTabSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(mobilityActiveTabProvider);
    final notifier = ref.read(mobilityProvider.notifier);

    return MobilityDualTabSwitcher(
      activeIndex: activeTab,
      onChanged: (index) {
        unawaited(notifier.setActiveTab(index));
      },
    );
  }
}

class MobilityDualTabSwitcher extends StatelessWidget {
  const MobilityDualTabSwitcher({
    required this.activeIndex,
    required this.onChanged,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Nearby Drivers', 'Scheduled Trips'];
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isActive = activeIndex == index;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isActive,
              label: '${labels[index]} tab',
              child: GestureDetector(
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[index],
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive ? onPrimary : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
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
    final activeTab = ref.watch(mobilityActiveTabProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final isLoading = ref.watch(mobilityDiscoveryLoadingProvider);
    final error = ref.watch(mobilityDiscoveryErrorProvider);
    final drivers = ref.watch(mobilityNearbyDriversProvider);
    final trips = ref.watch(mobilityScheduledTripsProvider);

    return switch (activeTab) {
      0 => SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _buildDriverSliver(
          locationState: locationState,
          isLoading: isLoading,
          error: error,
          drivers: drivers,
        ),
      ),
      _ => SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _buildTripSliver(
          locationState: locationState,
          isLoading: isLoading,
          error: error,
          trips: trips,
          onTripPreviewTap: onTripPreviewTap,
        ),
      ),
    };
  }

  Widget _buildDriverSliver({
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
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    super.key,
  });

  final List<DriverInfo> drivers;
  final ValueChanged<DriverInfo> onPreviewTap;
  final ValueChanged<DriverInfo> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return _MobilityStatusSliver(
        message: 'No drivers found for this vehicle type.',
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Text(
            'Top 30 within 10 km · nearest first',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
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
                rating: driver.rating ?? 0,
                tripCount: driver.tripCount ?? 0,
                scheduledRoute: driver.scheduledRoute,
                hasReturnTrip: driver.hasReturnTrip,
                baseLocation: driver.baseLocation,
                vehicleStatus: driver.vehicleStatus,
                isRegularDriver: driver.isRegularDriver,
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
      return _MobilityStatusSliver(message: 'No scheduled trips found nearby.');
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Text(
            'Upcoming trips near you',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
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
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
