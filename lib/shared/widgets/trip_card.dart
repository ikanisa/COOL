import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A card showing trip details: route (from → to), departure time,
/// vehicle info, and optional return / recurring indicators.
///
/// Tapping the card triggers [onTap].
class TripCard extends StatelessWidget {
  const TripCard({
    required this.fromLocation,
    required this.toLocation,
    required this.departureTime,
    required this.vehicleType,
    required this.vehicleEmoji,
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
  final String vehicleEmoji;
  final VoidCallback onTap;
  final int? seats;
  final bool isReturn;
  final bool isRecurring;
  final bool isDriverReturnTrip;

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Formatted departure string: "Thu 12 Mar / 08:30 AM / in 18h"
  String get _formattedDeparture {
    final now = DateTime.now();
    final diff = departureTime.difference(now);

    final dayName = _weekday(departureTime.weekday);
    final month = _month(departureTime.month);
    final day = departureTime.day;
    final hour = departureTime.hour % 12 == 0 ? 12 : departureTime.hour % 12;
    final minute = departureTime.minute.toString().padLeft(2, '0');
    final period = departureTime.hour >= 12 ? 'PM' : 'AM';

    final relativeStr = _relativeTime(diff);

    return '$dayName $day $month / $hour:$minute $period / $relativeStr';
  }

  bool get _isExpiringSoon {
    final diff = departureTime.difference(DateTime.now());
    return diff.inMinutes > 0 && diff.inMinutes < 60;
  }

  bool get _hasDeparted => departureTime.isBefore(DateTime.now());

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

  static String _relativeTime(Duration diff) {
    if (diff.isNegative) return 'departed';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return 'in ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
                  color: _isExpiringSoon || _hasDeparted
                      ? AppColors.red
                      : AppColors.text3,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formattedDeparture,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _isExpiringSoon || _hasDeparted
                          ? AppColors.red
                          : AppColors.text2,
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
                  label: '$vehicleEmoji $vehicleType',
                  bgColor: AppColors.surface3,
                  textColor: AppColors.text2,
                ),

                // Seats
                if (seats != null)
                  _Chip(
                    label: '🪑 $seats',
                    bgColor: AppColors.surface3,
                    textColor: AppColors.text2,
                  ),

                // Return tag
                if (isReturn || isDriverReturnTrip)
                  _Chip(
                    label: '🔁 Return',
                    bgColor: AppColors.purple.withValues(alpha: 0.15),
                    textColor: AppColors.purple,
                  ),

                // Recurring tag
                if (isRecurring)
                  _Chip(
                    label: '🔄 Daily',
                    bgColor: AppColors.accentGlow,
                    textColor: AppColors.accent,
                  ),

                // Expiring warning
                if (_isExpiringSoon && !_hasDeparted)
                  _Chip(
                    label: '⚠ Expires soon',
                    bgColor: AppColors.red.withValues(alpha: 0.12),
                    textColor: AppColors.red,
                  ),
              ],
            ),
          ],
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
