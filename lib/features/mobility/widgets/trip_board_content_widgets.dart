import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/wa_button.dart';
import '../models/trip.dart';
import '../providers/discovery_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/trip_board_provider.dart';
import 'trip_display_strings.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

/// Whether a trip has a reachable contact phone.
bool hasContactPhone(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

bool isActiveTrip(Trip trip) {
  final s = trip.status.trim().toUpperCase();
  return s == 'OPEN' || s == 'MATCHED' || s == 'ACTIVE';
}

bool isPausedTrip(Trip trip) => trip.status.trim().toUpperCase() == 'PAUSED';

String vehicleIconForType(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return 'assets/icons/vehicle_moto.png';
  if (normalized.contains('cab') || normalized.contains('car')) {
    return 'assets/icons/vehicle_cab.png';
  }
  if (normalized.contains('truck')) return 'assets/icons/vehicle_truck.png';
  if (normalized.contains('pickup') || normalized.contains('others')) {
    return 'assets/icons/vehicle_others.png';
  }
  if (normalized.contains('trike') || normalized.contains('van')) {
    return 'assets/icons/vehicle_trike.png';
  }
  return 'assets/icons/vehicle_cab.png';
}

String displayVehicleType(String vehicleType) {
  switch (vehicleType.trim().toLowerCase()) {
    case 'moto':
      return 'Moto';
    case 'moto taxi':
      return 'Moto Taxi';
    case 'cab':
      return 'Cab';
    case 'truck':
      return 'Truck';
    case 'trike':
      return 'Trike';
    case 'others':
    case 'pickup':
      return 'Others';
    case 'any':
      return 'Any';
    default:
      return vehicleType;
  }
}

String myTripTypeLabel(Trip trip) => tripTypeLabelForTrip(trip);

// ── Slivers ──────────────────────────────────────────────────────────────

/// Public trips sliver (explore tab).
class TripBoardPublicTripsSliver extends ConsumerWidget {
  const TripBoardPublicTripsSliver({
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    super.key,
  });

  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(nearbyTripsProvider);
    final discoveryState = ref.watch(discoveryProvider);
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final isLoading = discoveryState.isTripsLoading;
    final error = discoveryState.error;
    final locationState = ref.watch(mobilityLocationProvider);
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);

    if (isLoading && trips.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: TripBoardLoadingState(
            title: 'Loading nearby trips',
            subtitle: 'Searching nearby…',
          ),
        ),
      );
    }

    if (!locationState.hasLocation) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: TripBoardLocationStateCard(
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

    if (error != null && trips.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: TripBoardEmptyState(
            icon: Icons.warning_amber_rounded,
            title: 'Load nearby trips failed',
            subtitle: error,
          ),
        ),
      );
    }

    if (activeTab == TripBoardTab.driverReturnTrips) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: _DriverReturnTripsSliver(
          trips: trips,
          onPreviewTap: onPreviewTap,
          onWhatsAppTap: onWhatsAppTap,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      sliver: _TripsTabSliver(
        trips: trips,
        emptyTitle: 'No passenger trips nearby',
        onPreviewTap: onPreviewTap,
        onWhatsAppTap: onWhatsAppTap,
        buttonLabelBuilder: (trip) =>
            hasContactPhone(trip) ? 'Join on WhatsApp' : 'No contact yet',
      ),
    );
  }
}

/// My trips sliver.
class TripBoardMyTripsSliver extends ConsumerWidget {
  const TripBoardMyTripsSliver({required this.onShowActions, super.key});

  final ValueChanged<Trip> onShowActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTrips = ref.watch(tripBoardMyTripsProvider);
    final isLoading = ref.watch(tripBoardMyTripsLoadingProvider);
    final actionTripId = ref.watch(tripBoardActionTripIdProvider);
    final error = ref.watch(tripBoardMyTripsErrorProvider);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (isLoading && myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: TripBoardLoadingState(
                title: 'Loading your trips',
                subtitle: 'Loading your trips…',
              ),
            )
          else if (error != null && myTrips.isEmpty)
            SliverToBoxAdapter(
              child: TripBoardEmptyState(
                icon: Icons.warning_amber_rounded,
                title: 'Load your trips failed',
                subtitle: error,
              ),
            )
          else if (myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: TripBoardEmptyState(
                icon: Icons.folder_open_rounded,
                title: 'No trips posted yet',
                subtitle: 'Post a trip to get started',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final trip = myTrips[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == myTrips.length - 1 ? 0 : 12,
                  ),
                  child: MyTripTile(
                    trip: trip,
                    isBusy: actionTripId == trip.id,
                    onShowActions: () => onShowActions(trip),
                  ),
                );
              }, childCount: myTrips.length),
            ),
        ],
      ),
    );
  }
}

class _TripsTabSliver extends StatelessWidget {
  const _TripsTabSliver({
    required this.trips,
    required this.emptyTitle,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    required this.buttonLabelBuilder,
  });

  final List<Trip> trips;
  final String emptyTitle;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;
  final String Function(Trip trip) buttonLabelBuilder;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return SliverToBoxAdapter(
        child: TripBoardEmptyState(
          icon: Icons.search_rounded,
          title: emptyTitle,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final trip = trips[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == trips.length - 1 ? 0 : 12),
          child: TripBoardTripTile(
            trip: trip,
            buttonLabel: buttonLabelBuilder(trip),
            onPreviewTap: () => onPreviewTap(trip),
            onWhatsAppTap: () => onWhatsAppTap(trip),
          ),
        );
      }, childCount: trips.length),
    );
  }
}

class _DriverReturnTripsSliver extends StatelessWidget {
  const _DriverReturnTripsSliver({
    required this.trips,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final List<Trip> trips;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (trips.isEmpty)
          const SliverToBoxAdapter(
            child: TripBoardEmptyState(
              icon: Icons.repeat_rounded,
              title: 'No driver returns available',
              subtitle: 'Try another vehicle type',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final trip = trips[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == trips.length - 1 ? 0 : 12,
                ),
                child: TripBoardTripTile(
                  trip: trip,
                  buttonLabel: hasContactPhone(trip)
                      ? 'Contact Driver'
                      : 'No contact yet',
                  onPreviewTap: () => onPreviewTap(trip),
                  onWhatsAppTap: () => onWhatsAppTap(trip),
                ),
              );
            }, childCount: trips.length),
          ),
      ],
    );
  }
}

// ── Tile widgets ─────────────────────────────────────────────────────────

/// A public trip tile with route, vehicle info, distance, and WhatsApp CTA.
class TripBoardTripTile extends StatelessWidget {
  const TripBoardTripTile({
    required this.trip,
    required this.buttonLabel,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    super.key,
  });

  final Trip trip;
  final String buttonLabel;
  final VoidCallback onPreviewTap;
  final VoidCallback onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final canContact = hasContactPhone(trip);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TripCard(
          fromLocation: trip.fromLocation,
          toLocation: trip.toLocation,
          departureTime: trip.departureTime,
          vehicleType: displayVehicleType(trip.vehicleType),
          onTap: onPreviewTap,
          seats: trip.seats,
          isReturn: trip.isReturn,
          isRecurring: trip.isRecurring,
          isDriverReturnTrip: trip.isDriverReturnTrip,
          distanceKm: trip.distanceKm,
          priceNote: trip.priceNote,
          statusLabel: isPausedTrip(trip)
              ? 'Paused'
              : isActiveTrip(trip)
              ? 'Open now'
              : 'Scheduled',
          demandLabel: trip.isDriverReturnTrip
              ? 'Driver return'
              : 'Immediate contact',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPreviewTap,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View details'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: colors.primaryText,
                  backgroundColor: colors.cardSurfaceStrong,
                  side: BorderSide(color: colors.border),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WaButton(
                label: buttonLabel,
                iconOnly: false,
                fullWidth: true,
                onTap: canContact ? onWhatsAppTap : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "My trip" tile with status badge and actions menu.
class MyTripTile extends StatelessWidget {
  const MyTripTile({
    required this.trip,
    required this.onShowActions,
    required this.isBusy,
    super.key,
  });

  final Trip trip;
  final VoidCallback onShowActions;
  final bool isBusy;

  bool get _isExpired => trip.status == 'expired';
  bool get _isCancelled => trip.status == 'cancelled';
  bool get _isMatched => trip.status == 'matched';
  bool get _isPaused => trip.status.toUpperCase() == 'PAUSED';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Opacity(
      opacity: _isExpired || _isCancelled || _isPaused ? 0.58 : 1,
      child: CoolCard(
        padding: const EdgeInsets.all(16),
        backgroundColor: colors.routeSurface,
        borderColor: colors.borderStrong,
        useGradient: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  vehicleIconForType(trip.vehicleType),
                  width: 22,
                  height: 22,
                  color: colors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trip.fromLocation} → ${trip.toLocation}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat(
                          'EEE d MMM • HH:mm',
                        ).format(trip.departureTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CupertinoActivityIndicator(radius: 10),
                  )
                else
                  IconButton(
                    onPressed: onShowActions,
                    tooltip: 'Trip actions',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: colors.secondaryText,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(label: displayVehicleType(trip.vehicleType)),
                      _InfoPill(label: myTripTypeLabel(trip)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _MyTripStatusBadge(
                  isExpired: _isExpired,
                  isCancelled: _isCancelled,
                  isPaused: _isPaused,
                  isMatched: _isMatched,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTripStatusBadge extends StatelessWidget {
  const _MyTripStatusBadge({
    required this.isExpired,
    required this.isCancelled,
    required this.isPaused,
    required this.isMatched,
  });

  final bool isExpired;
  final bool isCancelled;
  final bool isPaused;
  final bool isMatched;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    if (isExpired) {
      return StatusBadge(
        label: 'Expired',
        bgColor: colors.cardSurfaceStrong,
        textColor: colors.tertiaryText,
      );
    }
    if (isCancelled) {
      return StatusBadge(
        label: 'Cancelled',
        bgColor: colors.danger.withValues(alpha: 0.14),
        textColor: colors.danger,
      );
    }
    if (isPaused) {
      return StatusBadge(
        label: 'Paused',
        bgColor: colors.warning.withValues(alpha: 0.15),
        textColor: colors.warning,
      );
    }
    if (isMatched) {
      return StatusBadge(
        label: 'Matched',
        bgColor: colors.info.withValues(alpha: 0.14),
        textColor: colors.info,
      );
    }
    return StatusBadge(
      label: 'Active',
      bgColor: colors.accent.withValues(alpha: 0.12),
      textColor: colors.accent,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── State widgets ────────────────────────────────────────────────────────

/// Empty / error state card.
class TripBoardEmptyState extends StatelessWidget {
  const TripBoardEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onActionTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      padding: const EdgeInsets.all(20),
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 34, color: colors.secondaryText),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            if (actionLabel != null && onActionTap != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 180,
                child: CoolButton(label: actionLabel!, onTap: onActionTap!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading state card.
class TripBoardLoadingState extends StatelessWidget {
  const TripBoardLoadingState({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      padding: const EdgeInsets.all(20),
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        children: [
          const CupertinoActivityIndicator(radius: 12),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Location-state card that resolves the right message and CTA per location status.
class TripBoardLocationStateCard extends StatelessWidget {
  const TripBoardLocationStateCard({
    required this.locationState,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    super.key,
  });

  final MobilityLocationState locationState;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
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
        subtitle = 'Location access needed';
        break;
      case MobilityLocationStatus.accessDisabled:
        icon = Icons.admin_panel_settings_outlined;
        title = 'Location is off in COOL';
        subtitle = 'Location off in Profile';
        actionLabel = 'Enable Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        icon = Icons.pin_drop_rounded;
        title = 'Enable location';
        subtitle = 'Nearby matching needs access';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location blocked';
        subtitle = 'Open settings to allow';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.satellite_alt_rounded;
        title = 'Turn on device location';
        subtitle = 'Location services off';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        icon = Icons.pin_drop_rounded;
        title = 'Location ready';
        subtitle = 'Nearby matching available';
        break;
      case MobilityLocationStatus.error:
        icon = Icons.warning_amber_rounded;
        title = 'Location could not be resolved';
        subtitle = locationState.error ?? 'Refresh or enable location';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return TripBoardEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onActionTap: action,
    );
  }
}
