import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
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

String _tripStatusLabel(Trip trip) {
  final normalized = trip.status.trim().toUpperCase();
  if (normalized == 'PAUSED') {
    return 'Paused';
  }
  if (normalized == 'OPEN' ||
      normalized == 'MATCHED' ||
      normalized == 'ACTIVE') {
    return 'Open now';
  }
  return 'Scheduled';
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final locationState = ref.watch(mobilityLocationProvider);
    final hasDiscoveryLocation = locationState.hasLocation;
    final selectedTab = ref.watch(
      discoveryProvider.select((s) => s.selectedTab),
    );
    final activeTab = selectedTab == 1 ? 1 : 0;
    final discoveryState = ref.watch(discoveryProvider);
    final nearbyDriverCount = discoveryState.nearbyDrivers.length;
    final nearbyTripCount = discoveryState.nearbyTrips.length;

    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dispatch',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Drivers. Trips. Handoff.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Wrap(
            spacing: CoolSpace.x2,
            runSpacing: CoolSpace.x2,
            children: hasDiscoveryLocation
                ? [
                    _MobilitySignalChip(
                      icon: Icons.people_outline_rounded,
                      label: '$nearbyDriverCount drivers',
                      accentColor: colors.info,
                    ),
                    _MobilitySignalChip(
                      icon: Icons.alt_route_rounded,
                      label: '$nearbyTripCount trips',
                      accentColor: colors.accent,
                    ),
                    _MobilitySignalChip(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp ready',
                      accentColor: colors.warning,
                    ),
                  ]
                : [
                    _MobilitySignalChip(
                      icon: Icons.pin_drop_outlined,
                      label: 'Location needed',
                      accentColor: colors.warning,
                    ),
                    _MobilitySignalChip(
                      icon: Icons.edit_location_alt_outlined,
                      label: 'Trip setup',
                      accentColor: colors.info,
                    ),
                    _MobilitySignalChip(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp ready',
                      accentColor: colors.accent,
                    ),
                  ],
          ),
          const SizedBox(height: CoolSpace.x4),
          _MobilityTabBar(
            activeIndex: activeTab,
            onChanged: (index) {
              final notifier = ref.read(discoveryProvider.notifier);
              notifier.setSelectedTab(index);
              if (index == 0) {
                unawaited(notifier.loadNearbyDrivers());
              } else {
                unawaited(notifier.loadNearbyTrips());
              }
            },
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: 'Schedule Trip',
            fullWidth: false,
            icon: Icons.add_circle_outline_rounded,
            onTap: widget.onScheduleTrip,
          ),
          if (hasDiscoveryLocation) ...[
            const SizedBox(height: CoolSpace.x4),
            const MobilityFilterBar(),
          ],
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
    final selectedVehicle = ref.watch(
      discoveryProvider.select((s) => s.selectedVehicle),
    );
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
// 2-TAB BAR (Nearby Drivers | Trips)
// ═════════════════════════════════════════════════════════════════════════════

class _MobilityTabBar extends StatelessWidget {
  const _MobilityTabBar({required this.activeIndex, required this.onChanged});

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    const tabs = [
      (icon: Icons.people_outline_rounded, label: 'Nearby'),
      (icon: Icons.route_rounded, label: 'Trips'),
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
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
                    duration: CoolMotion.quick,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: activeIndex == i
                          ? colors.accent
                          : colors.cardSurfaceStrong.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
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
                              : colors.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tabs[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: activeIndex == i
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: activeIndex == i
                                      ? onPrimary
                                      : colors.secondaryText,
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
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);
    final isLoading = discoveryState.isLoading;
    final error = discoveryState.error;
    final drivers = discoveryState.nearbyDrivers;
    final trips = discoveryState.nearbyTrips;

    // We determine "tab" based on state for now (Drivers view is primary)
    final isTripsView = discoveryState.selectedTab == 1;

    if (!locationState.hasLocation) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: SliverToBoxAdapter(
          child: _MobilityLocationStateCard(
            locationState: locationState,
            onEnableLocation: () {
              unawaited(locationNotifier.requestForegroundAccess());
            },
            onOpenAppSettings: () {
              unawaited(locationNotifier.openAppSettings());
            },
            onOpenLocationSettings: () {
              unawaited(locationNotifier.openLocationSettings());
            },
          ),
        ),
      );
    }

    if (isTripsView) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _buildTripSliver(
          context: context,
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
        context,
        ref,
        locationState: locationState,
        isLoading: isLoading,
        error: error,
        drivers: drivers,
      ),
    );
  }

  Widget _buildDriverSliver(
    BuildContext context,
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
      return _MobilityStatusSliver(
        message: error,
        color: context.coolSemanticColors.danger,
      );
    }

    return MobilityNearbyDriversSliver(
      drivers: drivers,
      selectedVehicle: ref.watch(
        discoveryProvider.select((s) => s.selectedVehicle),
      ),
      onPreviewTap: onDriverPreviewTap,
      onWhatsAppTap: onDriverWhatsAppTap,
    );
  }

  Widget _buildTripSliver({
    required BuildContext context,
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
      return _MobilityStatusSliver(
        message: error,
        color: context.coolSemanticColors.danger,
      );
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
        const SliverToBoxAdapter(child: SizedBox(height: CoolSpace.x1)),
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
                rating: driver.rating,
                tripCount: driver.tripCount,
                scheduledRoute: driver.scheduledRoute,
                baseLocation: driver.baseLocation,
                vehicleStatus: driver.vehicleStatus,
                isRegularDriver: driver.isRegularDriver,
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
      return const _MobilityStatusSliver(message: 'No scheduled trips found');
    }

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: CoolSpace.x1)),
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
                distanceKm: trip.distanceKm,
                priceNote: trip.priceNote,
                statusLabel: _tripStatusLabel(trip),
                demandLabel: trip.isDriverReturnTrip
                    ? 'Return seat'
                    : 'Fast response',
              ),
            );
          }, childCount: trips.length),
        ),
      ],
    );
  }
}

class _MobilitySignalChip extends StatelessWidget {
  const _MobilitySignalChip({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilityLocationStateCard extends StatelessWidget {
  const _MobilityLocationStateCard({
    required this.locationState,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final MobilityLocationState locationState;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    late final IconData icon;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        icon = Icons.satellite_alt_rounded;
        title = 'Checking your location';
        subtitle = 'Nearby trips and drivers need location access.';
        break;
      case MobilityLocationStatus.accessDisabled:
        icon = Icons.admin_panel_settings_outlined;
        title = 'Location is off in COOL';
        subtitle = 'Enable location to load nearby drivers and trips.';
        actionLabel = 'Enable location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        icon = Icons.pin_drop_rounded;
        title = 'Allow location';
        subtitle = 'Nearby trips and drivers need location access.';
        actionLabel = 'Use current location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location blocked';
        subtitle = 'Open system settings to allow mobility access.';
        actionLabel = 'Open settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.location_off_rounded;
        title = 'Turn on device location';
        subtitle = 'Location services are off on this device.';
        actionLabel = 'Turn on location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.error:
        icon = Icons.warning_amber_rounded;
        title = 'Location unavailable';
        subtitle =
            locationState.error ?? 'Refresh or enable location to continue.';
        actionLabel = 'Retry';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        icon = Icons.pin_drop_rounded;
        title = 'Location ready';
        subtitle = 'Nearby trips and drivers are available.';
        break;
    }

    return CoolCard(
      backgroundColor: colors.routeSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  boxShadow: CoolShadows.floating(
                    Theme.of(context).brightness,
                    strength: 0.2,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: colors.primaryText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null && action != null) ...[
            const SizedBox(height: CoolSpace.x4),
            CoolButton(
              label: actionLabel,
              onTap: action,
              fullWidth: false,
              icon: Icons.my_location_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _MobilityStatusSliver extends StatelessWidget {
  const _MobilityStatusSliver({required this.message, this.color});

  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: color ?? colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
