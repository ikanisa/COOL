import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../providers/mobility_location_provider.dart';
import '../services/place_search_service.dart';
import 'driver_profile_models.dart';
import 'schedule_trip_place_search_sheet.dart';

class ScheduledTripsCard extends StatelessWidget {
  const ScheduledTripsCard({required this.trips, super.key});

  final List<ScheduledTripData> trips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    if (trips.isEmpty) {
      return CoolCard(
        backgroundColor: colors.routeSurface,
        borderColor: colors.borderStrong,
        useGradient: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No scheduled trips yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        children: [
          for (var index = 0; index < trips.length; index++) ...[
            ScheduledTripTile(trip: trips[index]),
            if (index != trips.length - 1)
              Divider(color: colors.divider, height: 1),
          ],
        ],
      ),
    );
  }
}

class ScheduledTripTile extends StatelessWidget {
  const ScheduledTripTile({required this.trip, super.key});

  final ScheduledTripData trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final chips = <String>[
      trip.vehicleLabel,
      if (trip.isReturnTrip) 'Return',
      if (trip.isRecurring) 'Daily',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.inputSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              tripVehicleIcon(trip.vehicleLabel),
              width: 21,
              height: 21,
              color: colors.accent,
            ),
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
                  formatTripDate(trip.departureTime),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in chips)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: chip == 'Return'
                              ? colors.chipSelectedBackground
                              : colors.chipBackground,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: chip == 'Return'
                                ? colors.info
                                : colors.border,
                          ),
                        ),
                        child: Text(
                          chip,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: chip == 'Return'
                                ? colors.primaryText
                                : colors.secondaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VehicleInfoCard extends StatelessWidget {
  const VehicleInfoCard({required this.vehicle, super.key});

  final VehicleData vehicle;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final statusColor = vehicle.statusColor(context);
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        children: [
          _VehicleInfoTile(
            label: context.l10n.vehicleType1,
            value: vehicle.type,
          ),
          Divider(color: colors.divider, height: 1),
          _VehicleInfoTile(
            label: context.l10n.plateNumber1,
            value: vehicle.plateNumber,
          ),
          Divider(color: colors.divider, height: 1),
          _VehicleInfoTile(
            label: context.l10n.baseLocation1,
            value: vehicle.baseLocation,
          ),
          Divider(color: colors.divider, height: 1),
          _VehicleInfoTile(
            label: context.l10n.verification,
            value: vehicle.status,
            valueColor: statusColor,
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoTile extends StatelessWidget {
  const _VehicleInfoTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: valueColor ?? colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class EditVehicleSheet extends ConsumerStatefulWidget {
  const EditVehicleSheet({required this.vehicle, super.key});

  final VehicleData vehicle;

  @override
  ConsumerState<EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends ConsumerState<EditVehicleSheet> {
  late final TextEditingController _vehicleTypeController;
  late final TextEditingController _plateNumberController;
  late final TextEditingController _baseLocationController;
  bool _isResolvingBaseLocation = false;

  @override
  void initState() {
    super.initState();
    _vehicleTypeController = TextEditingController(text: widget.vehicle.type);
    _plateNumberController = TextEditingController(
      text: widget.vehicle.plateNumber,
    );
    _baseLocationController = TextEditingController(
      text: widget.vehicle.baseLocation,
    );
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _plateNumberController.dispose();
    _baseLocationController.dispose();
    super.dispose();
  }

  Future<void> _openBaseLocationSearch() async {
    final result = await showPlaceSearchSheet(
      context,
      title: context.l10n.setBaseLocation,
      initialQuery: _baseLocationController.text.trim(),
      service: ref.read(placeSearchServiceProvider),
      near: ref.read(mobilityLocationProvider).position,
      languageTag: resolveIntlLocale(context),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _baseLocationController.text = result.label;
    });
  }

  Future<void> _save() async {
    if (_isResolvingBaseLocation) {
      return;
    }

    setState(() => _isResolvingBaseLocation = true);
    var baseLocation = _baseLocationController.text.trim();

    try {
      if (baseLocation.isNotEmpty) {
        final resolved = await ref
            .read(placeSearchServiceProvider)
            .geocodeQuery(
              baseLocation,
              near: ref.read(mobilityLocationProvider).position,
              languageTag: resolveIntlLocale(context),
            );
        if (!mounted) {
          return;
        }
        if (resolved != null) {
          baseLocation = resolved.label;
          _baseLocationController.text = baseLocation;
        }
      }

      Navigator.of(context).pop(
        VehicleData(
          type: _vehicleTypeController.text.trim(),
          plateNumber: _plateNumberController.text.trim(),
          baseLocation: baseLocation,
          status: widget.vehicle.status,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResolvingBaseLocation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Edit Vehicle',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        CoolTextField(
          label: context.l10n.vehicleType2,
          hint: 'Moto Taxi',
          controller: _vehicleTypeController,
          prefixIcon: Icons.directions_car_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        CoolTextField(
          label: context.l10n.plateNumber2,
          hint: 'RAB 123 C',
          controller: _plateNumberController,
          prefixIcon: Icons.pin_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        CoolTextField(
          label: context.l10n.baseLocation2,
          hint: 'Nyamirambo, Kigali',
          controller: _baseLocationController,
          prefixIcon: Icons.location_on_rounded,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _openBaseLocationSearch,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(context.l10n.searchGooglePlaces),
          ),
        ),
        const SizedBox(height: 20),
        CoolButton(
          label: context.l10n.saveVehicleInfo,
          onTap: _save,
          isLoading: _isResolvingBaseLocation,
        ),
      ],
    );
  }
}
