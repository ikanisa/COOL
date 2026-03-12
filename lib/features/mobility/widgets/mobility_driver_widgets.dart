import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';

/// Resolves an [IconData] for a given vehicle type string.
IconData mobilityVehicleIcon(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return Icons.two_wheeler_rounded;
  if (normalized.contains('cab')) return Icons.directions_car_rounded;
  if (normalized.contains('truck')) return Icons.local_shipping_rounded;
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return Icons.airport_shuttle_rounded;
  }
  return Icons.directions_car_filled_rounded;
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
  final IconData vehicleIcon;
  final String vehicleType;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
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
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(vehicleIcon, size: 22, color: AppColors.accent),
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
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleType,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
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
              color: isOnline ? AppColors.accentGlow : AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOnline ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.radio_button_checked : Icons.circle_outlined,
                  size: 14,
                  color: isOnline ? AppColors.accent : AppColors.text2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$stateLabel · $stateMessage',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isOnline ? AppColors.accent : AppColors.text2,
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
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 52,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.surface3,
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
    );
  }
}

/// Animated banner showing online/offline status.
class MobilityOnlineStatusBanner extends StatelessWidget {
  const MobilityOnlineStatusBanner({required this.isOnline, super.key});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(isOnline),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOnline ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOnline ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          isOnline ? '● Online — visible nearby' : '○ Offline',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isOnline ? AppColors.accent : AppColors.text2,
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
