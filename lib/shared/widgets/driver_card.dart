import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import 'status_badge.dart';
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
    required this.vehicleEmoji,
    required this.distanceKm,
    required this.isOnline,
    required this.onWhatsAppTap,
    this.rating,
    this.tripCount,
    this.scheduledRoute,
    this.hasReturnTrip = false,
    this.baseLocation,
    this.vehicleStatus,
    this.isRegularDriver = false,
    this.onTap,
    super.key,
  });

  final String driverId;
  final String displayName;
  final String vehicleType;
  final String vehicleEmoji;
  final double distanceKm;
  final bool isOnline;
  final VoidCallback onWhatsAppTap;
  final double? rating;
  final int? tripCount;
  final String? scheduledRoute;
  final bool hasReturnTrip;
  final String? baseLocation;
  final String? vehicleStatus;
  final bool isRegularDriver;
  final VoidCallback? onTap;

  String get _initials {
    final source = displayName.trim().isEmpty ? driverId : displayName.trim();
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
    final content = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: avatar + info + WA ──────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              _Avatar(initials: _initials, isOnline: isOnline),
              const SizedBox(width: 12),

              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.trim().isEmpty ? driverId : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Status badge
                    isOnline
                        ? const StatusBadge.online()
                        : const StatusBadge.offline(),
                    const SizedBox(height: 8),

                    // Vehicle chip
                    _VehicleChip(emoji: vehicleEmoji, type: vehicleType),
                    const SizedBox(height: 6),

                    // Distance + rating row
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.near_me_rounded,
                          label: _distanceLabel,
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: Icons.star_rounded,
                            label: rating!.toStringAsFixed(1),
                            iconColor: AppColors.yellow,
                          ),
                        ],
                        if (tripCount != null) ...[
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: Icons.route_rounded,
                            label: '$tripCount',
                          ),
                        ],
                      ],
                    ),
                    if (baseLocation != null &&
                        baseLocation!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        baseLocation!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // ── Scheduled route / trust metadata ────────────────────
          if (scheduledRoute != null ||
              isRegularDriver ||
              (vehicleStatus?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: AppColors.text3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      scheduledRoute ??
                          (isRegularDriver
                              ? 'Regular driver'
                              : _vehicleStatusLabel(vehicleStatus)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                      ),
                    ),
                  ),
                  if (hasReturnTrip || isRegularDriver) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isRegularDriver
                            ? AppColors.blueGlow
                            : AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        isRegularDriver ? '✔ Trusted' : '🔁 Return',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isRegularDriver
                              ? AppColors.blue
                              : AppColors.purple,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Footer action ───────────────────────────────────────
          Row(
            children: [
              if (onTap != null)
                Text(
                  'Tap for details',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text3,
                  ),
                ),
              const Spacer(),
              WaButton(onTap: onWhatsAppTap),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

String _vehicleStatusLabel(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'Driver listing';
  }

  return normalized
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
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
  const _VehicleChip({required this.emoji, required this.type});
  final String emoji;
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
          Text(emoji, style: const TextStyle(fontSize: 14)),
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
