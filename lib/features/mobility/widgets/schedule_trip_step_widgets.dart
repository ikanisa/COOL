import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/mobility_route_preview.dart';
import '../models/trip_post_request.dart';
import '../providers/mobility_location_provider.dart';
import '../services/place_search_service.dart';
import 'schedule_trip_route_preview.dart';

import 'schedule_trip_route_widgets.dart';
import 'schedule_trip_shared.dart';




// ── Data helpers ────────────────────────────────────────────────────

class VehicleOption {
  const VehicleOption({
    required this.value,
    required this.label,
    this.assetPath,
  });

  final TripVehiclePreference value;
  final String label;

  /// Path to the vehicle image asset, if available.
  final String? assetPath;
}

class DayOption {
  const DayOption({required this.day, required this.label});

  final TripWeekday day;
  final String label;
}

/// F-11: Dynamic seat options based on vehicle type.
List<int> seatOptionsFor(TripVehiclePreference vehicle) {
  return switch (vehicle) {
    TripVehiclePreference.truck || TripVehiclePreference.trike =>
      const <int>[1, 2, 3, 5, 8],
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
    VehicleOption(
      value: TripVehiclePreference.any,
      label: l10n.vehicleAny,
    ),
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

// ── Route step ────────────────────────────────────────────────────

/// Step 1: Route – pickup and destination input.
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
    required this.resolvingTypedRoute,
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
  final bool resolvingTypedRoute;
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final title = isDriverPosting ? 'Return route' : 'Pickup and destination';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface2,
              palette.surface3,
            ],
          ),
          borderColor: Colors.white.withValues(alpha: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 16),
              ScheduleTripRouteEditor(
                fromController: fromController,
                toController: toController,
                fromHint: l10n.scheduleTripFromHint,
                toHint: l10n.scheduleTripToHint,
                fromResolved: fromSelection != null,
                toResolved: toSelection != null,
                isResolvingCurrentLocation: isResolvingCurrentLocation,
                onFromSearchTap: onFromSearchTap,
                onToSearchTap: onToSearchTap,
                onUseCurrentLocationTap: onUseCurrentLocationTap,
                fromValidator: fromValidator,
                toValidator: toValidator,
                fromHintText: fromSelection != null
                    ? 'Google pickup pin attached.'
                    : 'Search Google Places or use current location.',
                toHintText: toSelection != null
                    ? 'Google destination pin attached.'
                    : 'Search Google Places for a destination.',
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
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

// ── Timing step ───────────────────────────────────────────────────

/// Step 2: Timing – date/time, return trip, recurring.
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final dayOptions = buildDayOptions(context);
    final title = isDriverPosting ? 'Departure timing' : 'When';
    final extraTitle = isDriverPosting
        ? 'Extra scheduling'
        : 'Repeat';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface2,
              palette.surface3,
            ],
          ),
          borderColor: Colors.white.withValues(alpha: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 16),
              ScheduleTripFieldLabel(label: l10n.scheduleTripDateTimeLabel),
              const SizedBox(height: 8),
              ScheduleTripAdaptiveFieldPair(
                first: ScheduleTripPickerField(
                  prefix: l10n.scheduleTripDateFieldPrefix,
                  value: formatDate(selectedDate),
                  onTap: onPickDate,
                ),
                second: ScheduleTripPickerField(
                  prefix: l10n.scheduleTripTimeFieldPrefix,
                  value: formatTime(selectedTime),
                  onTap: onPickTime,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                extraTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 12),
              ScheduleTripToggleCard(
                icon: Icons.sync_rounded,
                title: l10n.scheduleTripRecurringTitle,
                subtitle: l10n.scheduleTripRecurringSubtitle,
                value: recurringTrip,
                onChanged: onRecurringTripToggled,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: !recurringTrip
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScheduleTripFieldLabel(
                              label: l10n.scheduleTripRecurringDaysLabel,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in dayOptions)
                                  ScheduleTripDayChip(
                                    label: option.label,
                                    selected: recurringDays.contains(
                                      option.day,
                                    ),
                                    onTap: () =>
                                        onRecurringDayToggled(option.day),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Options step ──────────────────────────────────────────────────

/// Step 3: Options – vehicle, seats, price note.
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final vehicleOptions = buildVehicleOptions(context);
    final normalizedVehicle = driverVehicleLabel?.trim() ?? '';
    final hasDriverVehicle = isDriverPosting && normalizedVehicle.isNotEmpty;
    final headerTitle = isDriverPosting ? 'Driver return setup' : 'Trip setup';
    final seatsLabel = isDriverPosting
        ? 'Seats available'
        : l10n.scheduleTripSeatsLabel;
    final detailsTitle = isDriverPosting ? 'Rider note' : 'Add details';
    final noteFieldLabel = isDriverPosting
        ? 'Rider note (optional)'
        : 'Price note (optional)';
    final noteHint = isDriverPosting
        ? 'e.g. 500 RWF · Pickup near main road'
        : 'e.g. 500 RWF · Negotiable';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface2,
              palette.surface3,
            ],
          ),
          borderColor: Colors.white.withValues(alpha: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              if (hasDriverVehicle) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.directions_car_filled_rounded,
                        size: 18,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Posting vehicle',
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: palette.text,
                              ),
                            ),
                            Text(
                              normalizedVehicle,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: palette.text2,
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
                      ? 'Vehicle for this trip'
                      : l10n.scheduleTripVehicleLabel,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleDetails,
                    child: Text(showAdditionalDetails ? 'Hide' : 'Show'),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
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
                        color: palette.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: palette.text2,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.scheduleTripExpiryTitle,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: palette.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.scheduleTripExpirySubtitle,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: palette.text2,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: palette.text,
                      ),
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: noteHint,
                        hintStyle: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: palette.text3,
                        ),
                        counterStyle: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: palette.text3,
                        ),
                        filled: true,
                        fillColor: palette.surface3,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: palette.accent,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
