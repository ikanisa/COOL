import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/identity/public_user_identity.dart';
import '../../core/theme/app_colors.dart';

import 'wa_button.dart';

/// A card displaying driver information for the mobility feature.
///
/// Shows initials avatar, online/offline badge, distance, rating,
/// vehicle chip, and a WhatsApp action button. The driver's phone
/// number is **never** displayed — only the WA button.
class DriverCard extends StatelessWidget {
  const DriverCard({
    required this.driverId,
    required this.displayName,
    required this.vehicleType,
    required this.distanceKm,
    required this.isOnline,
    required this.onWhatsAppTap,
    this.onTap,
    super.key,
  });

  final String driverId;
  final String displayName;
  final String vehicleType;
  final double distanceKm;
  final bool isOnline;
  final VoidCallback onWhatsAppTap;
  final VoidCallback? onTap;

  String get _initials {
    final source = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: driverId,
    );
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'DR';
    }
    if (parts.length == 1) {
      final value = parts.first;
      return value.length >= 2
          ? value.substring(0, 2).toUpperCase()
          : value.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get _distanceLabel {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final name = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: driverId,
    );
    final content = Semantics(
      label:
          '$name. $vehicleType. $_distanceLabel away.'
          '${isOnline ? 'Online' : 'Offline'}.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            _Avatar(initials: _initials, isOnline: isOnline),
            const SizedBox(width: 10),

            // Info column — compact
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _VehicleChip(
                        icon: _vehicleIconFromType(vehicleType),
                        type: vehicleType,
                      ),
                      const SizedBox(width: 6),
                      _InfoChip(
                        icon: Icons.near_me_rounded,
                        label: _distanceLabel,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // WA button — inline right
            WaButton(onTap: onWhatsAppTap),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

/// Maps a vehicle type string to an asset image path.
String _vehicleIconFromType(String vehicleType) {
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



// ── Avatar with online indicator ────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.isOnline});
  final String initials;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accentGlow,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border2),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface2, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Vehicle chip ────────────────────────────────────────────────────────

class _VehicleChip extends StatelessWidget {
  const _VehicleChip({required this.icon, required this.type});
  final String icon;
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(icon, width: 14, height: 14, color: AppColors.text2),
          const SizedBox(width: 4),
          Text(
            type,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info chip ───────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.iconColor});
  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? AppColors.text3),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }
}
