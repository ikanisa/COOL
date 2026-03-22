import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';

/// Resolves an Image asset path for a given vehicle type string.
String mobilityVehicleIcon(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return 'assets/icons/vehicle_moto.png';
  if (normalized.contains('cab') || normalized.contains('car')) return 'assets/icons/vehicle_cab.png';
  if (normalized.contains('truck')) return 'assets/icons/vehicle_truck.png';
  if (normalized.contains('pickup') || normalized.contains('others')) return 'assets/icons/vehicle_others.png';
  if (normalized.contains('trike') || normalized.contains('van')) {
    return 'assets/icons/vehicle_trike.png';
  }
  return 'assets/icons/vehicle_cab.png';
}

/// Toggle card for driver online/offline status.
class MobilityDriverToggleCard extends StatelessWidget {
  const MobilityDriverToggleCard({
    required this.isOnline,
    required this.vehicleIcon,
    required this.vehicleType,
    required this.onChanged,
    super.key,
  });

  final bool isOnline;
  final String vehicleIcon;
  final String vehicleType;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final stateLabel = isOnline ? 'Online now' : 'Offline';
    final stateMessage = isOnline
        ? 'Visible to nearby riders.'
        : 'Hidden until you go online.';

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  vehicleIcon,
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver mode',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleType,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
              MobilityDriverModeToggle(value: isOnline, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isOnline ? palette.accentGlow : palette.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOnline ? palette.accent : palette.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.radio_button_checked : Icons.circle_outlined,
                  size: 14,
                  color: isOnline ? palette.accent : palette.text2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$stateLabel · $stateMessage',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isOnline ? palette.accent : palette.text2,
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

/// Custom animated toggle for driver mode.
class MobilityDriverModeToggle extends StatelessWidget {
  const MobilityDriverModeToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      toggled: value,
      label: value ? 'Driver mode on' : 'Driver mode off',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 52,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? palette.accent : palette.surface3,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated banner showing online/offline status.
class MobilityOnlineStatusBanner extends StatelessWidget {
  const MobilityOnlineStatusBanner({required this.isOnline, super.key});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(isOnline),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOnline ? palette.accentGlow : palette.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOnline ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          isOnline ? '● Online — visible nearby' : '○ Offline',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isOnline ? palette.accent : palette.text2,
          ),
        ),
      ),
    );
  }
}

/// Composite section with driver toggle card + online status banner.
class MobilityDriverStatusSection extends StatelessWidget {
  const MobilityDriverStatusSection({
    required this.isOnline,
    required this.vehicleType,
    required this.onChanged,
    super.key,
  });

  final bool isOnline;
  final String vehicleType;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MobilityDriverToggleCard(
      isOnline: isOnline,
      vehicleIcon: mobilityVehicleIcon(vehicleType),
      vehicleType: vehicleType,
      onChanged: onChanged,
    );
  }
}
