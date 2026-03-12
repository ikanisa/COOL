import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import 'driver_profile_models.dart';

/// Card displaying a list of scheduled trips, or an empty-state message.
class ScheduledTripsCard extends StatelessWidget {
  const ScheduledTripsCard({required this.trips, super.key});

  final List<ScheduledTripData> trips;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return CoolCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No scheduled trips yet.',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ),
        ),
      );
    }

    return CoolCard(
      child: Column(
        children: [
          for (var index = 0; index < trips.length; index++) ...[
            ScheduledTripTile(trip: trips[index]),
            if (index != trips.length - 1)
              const Divider(color: AppColors.border, height: 1),
          ],
        ],
      ),
    );
  }
}

/// Single trip row inside the scheduled trips card.
class ScheduledTripTile extends StatelessWidget {
  const ScheduledTripTile({required this.trip, super.key});

  final ScheduledTripData trip;

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              tripVehicleIcon(trip.vehicleLabel),
              size: 21,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip.fromLocation} → ${trip.toLocation}',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatTripDate(trip.departureTime),
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
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
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: chip == 'Return'
                              ? AppColors.blueGlow
                              : AppColors.surface3,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          chip,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: chip == 'Return'
                                ? AppColors.blue
                                : AppColors.text2,
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

/// Card showing vehicle info tiles.
class VehicleInfoCard extends StatelessWidget {
  const VehicleInfoCard({required this.vehicle, super.key});

  final VehicleData vehicle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          _VehicleInfoTile(label: 'Vehicle Type', value: vehicle.type),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(label: 'Description', value: vehicle.plateNumber),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(label: 'Driver Type', value: vehicle.baseLocation),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(
            label: 'Availability',
            value: vehicle.status,
            valueColor: vehicle.statusColor,
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
    this.valueColor = AppColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for editing vehicle info.
class EditVehicleSheet extends StatefulWidget {
  const EditVehicleSheet({required this.vehicle, super.key});

  final VehicleData vehicle;

  @override
  State<EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<EditVehicleSheet> {
  late final TextEditingController _vehicleTypeController;
  late final TextEditingController _plateNumberController;
  late final TextEditingController _baseLocationController;
  late String _status;

  static const _statuses = ['Verified', 'Pending Review', 'Maintenance'];

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
    _status = widget.vehicle.status;
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _plateNumberController.dispose();
    _baseLocationController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      VehicleData(
        type: _vehicleTypeController.text.trim(),
        plateNumber: _plateNumberController.text.trim(),
        baseLocation: _baseLocationController.text.trim(),
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Edit Vehicle',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),
              CoolTextField(
                label: 'Vehicle Type',
                hint: 'Moto Taxi',
                controller: _vehicleTypeController,
                prefixEmoji: '🛺',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              CoolTextField(
                label: 'Plate Number',
                hint: 'RAB 123 C',
                controller: _plateNumberController,
                prefixEmoji: '🔢',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              CoolTextField(
                label: 'Base Location',
                hint: 'Nyamirambo, Kigali',
                controller: _baseLocationController,
                prefixEmoji: '📍',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              Text(
                'Status',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _statuses)
                    _VehicleStatusChip(
                      label: option,
                      isSelected: _status == option,
                      onTap: () => setState(() => _status = option),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              CoolButton(label: 'Save Vehicle Info', onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleStatusChip extends StatelessWidget {
  const _VehicleStatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
