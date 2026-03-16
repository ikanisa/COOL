import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A card showing the route, departure time, and the key trip chips.
///
/// Tapping the card triggers [onTap].
class TripCard extends StatelessWidget {
  const TripCard({
    required this.fromLocation,
    required this.toLocation,
    required this.departureTime,
    required this.vehicleType,
    required this.onTap,
    this.seats,
    this.isReturn = false,
    this.isRecurring = false,
    this.isDriverReturnTrip = false,
    super.key,
  });

  final String fromLocation;
  final String toLocation;
  final DateTime departureTime;
  final String vehicleType;
  final VoidCallback onTap;
  final int? seats;
  final bool isReturn;
  final bool isRecurring;
  final bool isDriverReturnTrip;

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Formatted departure string: "Thu 12 Mar · 08:30 AM"
  String get _formattedDeparture {
    final dayName = _weekday(departureTime.weekday);
    final month = _month(departureTime.month);
    final day = departureTime.day;
    final hour = departureTime.hour % 12 == 0 ? 12 : departureTime.hour % 12;
    final minute = departureTime.minute.toString().padLeft(2, '0');
    final period = departureTime.hour >= 12 ? 'PM' : 'AM';
    return '$dayName $day $month · $hour:$minute $period';
  }

  static String _weekday(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];

  static String _month(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Trip card',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Route (from → to) ─────────────────────────────────
              _RouteLine(dotColor: AppColors.accent, location: fromLocation),
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Container(
                  width: 1.5,
                  height: 16,
                  color: AppColors.border2,
                ),
              ),
              _RouteLine(dotColor: AppColors.orange, location: toLocation),
              const SizedBox(height: 14),

              // ── Time row ──────────────────────────────────────────
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: AppColors.text3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formattedDeparture,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Bottom row: vehicle + tags ─────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  // Vehicle chip
                  _Chip(
                    label: vehicleType,
                    bgColor: AppColors.surface3,
                    textColor: AppColors.text2,
                  ),

                  // Seats
                  if (seats != null)
                    _Chip(
                      label: '$seats seat${seats! > 1 ? 's' : ''}',
                      bgColor: AppColors.surface3,
                      textColor: AppColors.text2,
                    ),

                  if (isReturn || isDriverReturnTrip)
                    _Chip(
                      label: 'Return',
                      bgColor: AppColors.purple.withValues(alpha: 0.15),
                      textColor: AppColors.purple,
                    ),
                  if (isRecurring)
                    const _Chip(
                      label: 'Repeat',
                      bgColor: AppColors.accentGlow,
                      textColor: AppColors.accent,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Route line (dot + location text) ────────────────────────────────────

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.dotColor, required this.location});
  final Color dotColor;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Small pill chip ─────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });
  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
