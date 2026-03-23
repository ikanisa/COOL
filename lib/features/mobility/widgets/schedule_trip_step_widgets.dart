import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/mobility_route_preview.dart';
import '../models/trip_post_request.dart';
import '../providers/mobility_location_provider.dart';
import '../services/place_search_service.dart';
import 'schedule_trip_route_preview.dart';
import 'schedule_trip_route_widgets.dart';
import 'schedule_trip_shared.dart';

class VehicleOption {
  const VehicleOption({
    required this.value,
    required this.label,
    this.assetPath,
  });

  final TripVehiclePreference value;
  final String label;
  final String? assetPath;
}

class DayOption {
  const DayOption({required this.day, required this.label});

  final TripWeekday day;
  final String label;
}

List<int> seatOptionsFor(TripVehiclePreference vehicle) {
  return switch (vehicle) {
    TripVehiclePreference.truck ||
    TripVehiclePreference.trike => const <int>[1, 2, 3, 5, 8],
    TripVehiclePreference.moto => const <int>[1],
    _ => const <int>[1, 2, 3],
  };
}

List<VehicleOption> buildVehicleOptions(BuildContext context) {
  final l10n = context.l10n;
  return <VehicleOption>[
    VehicleOption(
      value: TripVehiclePreference.moto,
      label: l10n.vehicleMoto,
      assetPath: 'assets/icons/vehicle_moto.png',
    ),
    VehicleOption(
      value: TripVehiclePreference.cab,
      label: l10n.vehicleCab,
      assetPath: 'assets/icons/vehicle_cab.png',
    ),
    const VehicleOption(
      value: TripVehiclePreference.trike,
      label: 'Trike',
      assetPath: 'assets/icons/vehicle_trike.png',
    ),
    const VehicleOption(
      value: TripVehiclePreference.truck,
      label: 'Truck',
      assetPath: 'assets/icons/vehicle_truck.png',
    ),
    const VehicleOption(
      value: TripVehiclePreference.others,
      label: 'Others',
      assetPath: 'assets/icons/vehicle_others.png',
    ),
    VehicleOption(value: TripVehiclePreference.any, label: l10n.vehicleAny),
  ];
}

List<DayOption> buildDayOptions(BuildContext context) {
  final l10n = context.l10n;
  return <DayOption>[
    DayOption(day: TripWeekday.mon, label: l10n.weekdayMonShort),
    DayOption(day: TripWeekday.tue, label: l10n.weekdayTueShort),
    DayOption(day: TripWeekday.wed, label: l10n.weekdayWedShort),
    DayOption(day: TripWeekday.thu, label: l10n.weekdayThuShort),
    DayOption(day: TripWeekday.fri, label: l10n.weekdayFriShort),
    DayOption(day: TripWeekday.sat, label: l10n.weekdaySatShort),
    DayOption(day: TripWeekday.sun, label: l10n.weekdaySunShort),
  ];
}

class ScheduleTripRouteStep extends StatelessWidget {
  const ScheduleTripRouteStep({
    required this.isDriverPosting,
    required this.fromController,
    required this.toController,
    required this.fromSelection,
    required this.toSelection,
    required this.isResolvingCurrentLocation,
    required this.routePreview,
    required this.loadingRoutePreview,
    required this.routePreviewError,
    required this.locationState,
    required this.shouldShowLocationCard,
    required this.onFromSearchTap,
    required this.onToSearchTap,
    required this.onUseCurrentLocationTap,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    required this.fromValidator,
    required this.toValidator,
    super.key,
  });

  final bool isDriverPosting;
  final TextEditingController fromController;
  final TextEditingController toController;
  final PlaceSearchResult? fromSelection;
  final PlaceSearchResult? toSelection;
  final bool isResolvingCurrentLocation;
  final MobilityRoutePreview? routePreview;
  final bool loadingRoutePreview;
  final String? routePreviewError;
  final MobilityLocationState locationState;
  final bool shouldShowLocationCard;
  final VoidCallback onFromSearchTap;
  final VoidCallback onToSearchTap;
  final VoidCallback onUseCurrentLocationTap;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;
  final String? Function(String?) fromValidator;
  final String? Function(String?) toValidator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final title = isDriverPosting ? 'Return route' : 'Route';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          backgroundColor: colors.routeSurface,
          borderColor: colors.borderStrong,
          useGradient: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              ScheduleTripRouteEditor(
                fromController: fromController,
                toController: toController,
                fromHint: context.l10n.scheduleTripFromHint,
                toHint: context.l10n.scheduleTripToHint,
                fromResolved: fromSelection != null,
                toResolved: toSelection != null,
                isResolvingCurrentLocation: isResolvingCurrentLocation,
                onFromSearchTap: onFromSearchTap,
                onToSearchTap: onToSearchTap,
                onUseCurrentLocationTap: onUseCurrentLocationTap,
                fromValidator: fromValidator,
                toValidator: toValidator,
                fromHintText: fromSelection != null
                    ? 'Pickup attached.'
                    : 'Search or use location.',
                toHintText: toSelection != null
                    ? 'Destination attached.'
                    : 'Search destination.',
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: CoolMotion.standard,
          curve: CoolMotion.enterCurve,
          alignment: Alignment.topCenter,
          child:
              fromSelection == null &&
                  toSelection == null &&
                  !loadingRoutePreview &&
                  (routePreviewError?.trim().isEmpty ?? true)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ScheduleTripRoutePreview(
                    originLabel:
                        fromSelection?.primaryText ??
                        fromController.text.trim(),
                    destinationLabel:
                        toSelection?.primaryText ?? toController.text.trim(),
                    origin: fromSelection?.position,
                    destination: toSelection?.position,
                    preview: routePreview,
                    isLoading: loadingRoutePreview,
                    error: routePreviewError,
                  ),
                ),
        ),
        if (shouldShowLocationCard) ...[
          const SizedBox(height: 12),
          ScheduleTripLocationAttachmentCard(
            locationState: locationState,
            onEnableLocation: onEnableLocation,
            onOpenAppSettings: onOpenAppSettings,
            onOpenLocationSettings: onOpenLocationSettings,
          ),
        ],
      ],
    );
  }
}

class ScheduleTripTimingStep extends StatelessWidget {
  const ScheduleTripTimingStep({
    required this.isDriverPosting,
    required this.selectedDate,
    required this.selectedTime,
    required this.recurringTrip,
    required this.recurringDays,
    required this.formatDate,
    required this.formatTime,
    required this.onPickDate,
    required this.onPickTime,
    required this.onRecurringTripToggled,
    required this.onRecurringDayToggled,
    super.key,
  });

  final bool isDriverPosting;
  final DateTime selectedDate;
  final TimeOfDay selectedTime;
  final bool recurringTrip;
  final Set<TripWeekday> recurringDays;
  final String Function(DateTime) formatDate;
  final String Function(TimeOfDay) formatTime;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final ValueChanged<bool> onRecurringTripToggled;
  final void Function(TripWeekday) onRecurringDayToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final dayOptions = buildDayOptions(context);
    final title = isDriverPosting ? 'Departure' : 'Timing';

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ScheduleTripFieldLabel(label: context.l10n.scheduleTripDateTimeLabel),
          const SizedBox(height: 8),
          ScheduleTripAdaptiveFieldPair(
            first: ScheduleTripPickerField(
              prefix: context.l10n.scheduleTripDateFieldPrefix,
              value: formatDate(selectedDate),
              onTap: onPickDate,
            ),
            second: ScheduleTripPickerField(
              prefix: context.l10n.scheduleTripTimeFieldPrefix,
              value: formatTime(selectedTime),
              onTap: onPickTime,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Repeat',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ScheduleTripToggleCard(
            icon: Icons.sync_rounded,
            title: context.l10n.scheduleTripRecurringTitle,
            subtitle: context.l10n.scheduleTripRecurringSubtitle,
            value: recurringTrip,
            onChanged: onRecurringTripToggled,
          ),
          AnimatedSize(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            child: !recurringTrip
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScheduleTripFieldLabel(
                          label: context.l10n.scheduleTripRecurringDaysLabel,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in dayOptions)
                              ScheduleTripDayChip(
                                label: option.label,
                                selected: recurringDays.contains(option.day),
                                onTap: () => onRecurringDayToggled(option.day),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ScheduleTripOptionsStep extends StatelessWidget {
  const ScheduleTripOptionsStep({
    required this.isDriverPosting,
    required this.driverVehicleLabel,
    required this.vehiclePreference,
    required this.seats,
    required this.showAdditionalDetails,
    required this.priceNoteController,
    required this.onVehicleChanged,
    required this.onSeatChanged,
    required this.onToggleDetails,
    super.key,
  });

  final bool isDriverPosting;
  final String? driverVehicleLabel;
  final TripVehiclePreference vehiclePreference;
  final int seats;
  final bool showAdditionalDetails;
  final TextEditingController priceNoteController;
  final void Function(TripVehiclePreference) onVehicleChanged;
  final ValueChanged<int> onSeatChanged;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final vehicleOptions = buildVehicleOptions(context);
    final normalizedVehicle = driverVehicleLabel?.trim() ?? '';
    final hasDriverVehicle = isDriverPosting && normalizedVehicle.isNotEmpty;
    final headerTitle = isDriverPosting ? 'Driver setup' : 'Trip setup';
    final seatsLabel = isDriverPosting
        ? 'Seats available'
        : context.l10n.scheduleTripSeatsLabel;
    final detailsTitle = isDriverPosting ? 'Rider note' : 'Add details';
    final noteFieldLabel = isDriverPosting ? 'Rider note' : 'Price note';
    final noteHint = isDriverPosting
        ? 'e.g. 500 RWF · Pickup near main road'
        : 'e.g. 500 RWF · Negotiable';

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headerTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hasDriverVehicle) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.cardSurfaceStrong,
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.directions_car_filled_rounded,
                    size: 18,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Posting vehicle',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          normalizedVehicle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            ScheduleTripFieldLabel(
              label: isDriverPosting
                  ? 'Vehicle'
                  : context.l10n.scheduleTripVehicleLabel,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in vehicleOptions)
                  ScheduleTripVehicleChip(
                    label: option.label,
                    selected: vehiclePreference == option.value,
                    onTap: () => onVehicleChanged(option.value),
                    assetPath: option.assetPath,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          ScheduleTripFieldLabel(label: seatsLabel),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seat in seatOptionsFor(vehiclePreference))
                ScheduleTripSeatChip(
                  label: '$seat',
                  selected: seats == seat,
                  onTap: () => onSeatChanged(seat),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  detailsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onToggleDetails,
                child: Text(
                  showAdditionalDetails ? 'Hide' : 'Show',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: CoolMotion.quick,
            crossFadeState: showAdditionalDetails
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 12),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardSurfaceStrong,
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: colors.secondaryText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.scheduleTripExpiryTitle,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.scheduleTripExpirySubtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.secondaryText,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ScheduleTripFieldLabel(label: noteFieldLabel),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceNoteController,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: noteHint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.tertiaryText,
                      fontWeight: FontWeight.w600,
                    ),
                    counterStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colors.tertiaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: colors.inputSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      borderSide: BorderSide(color: colors.accent, width: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
