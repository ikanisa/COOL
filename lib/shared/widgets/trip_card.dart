import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

/// Premium route listing with route blocks, timing, demand, and trust status.
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
    this.distanceKm,
    this.priceNote,
    this.statusLabel,
    this.demandLabel,
    this.statusColor,
    this.demandColor,
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
  final double? distanceKm;
  final String? priceNote;
  final String? statusLabel;
  final String? demandLabel;
  final Color? statusColor;
  final Color? demandColor;

  String get _formattedDeparture {
    final dayName = _weekday(departureTime.weekday);
    final month = _month(departureTime.month);
    final day = departureTime.day;
    final hour = departureTime.hour % 12 == 0 ? 12 : departureTime.hour % 12;
    final minute = departureTime.minute.toString().padLeft(2, '0');
    final period = departureTime.hour >= 12 ? 'PM' : 'AM';
    return '$dayName $day $month · $hour:$minute $period';
  }

  String? get _distanceLabel {
    if (distanceKm == null) {
      return null;
    }
    if (distanceKm! < 1) {
      return '${(distanceKm! * 1000).round()} m away';
    }
    return '${distanceKm!.toStringAsFixed(1)} km away';
  }

  static String _weekday(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  static String _month(int month) => const [
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
  ][month - 1];

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final effectiveStatusColor = statusColor ?? palette.accent;
    final effectiveDemandColor = demandColor ?? palette.orange;

    return Semantics(
      button: true,
      label:
          '$fromLocation to $toLocation. $_formattedDeparture. ${statusLabel ?? 'Open listing'}.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.routeSurface,
            gradient: colors.surfaceGradient,
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            border: Border.all(color: colors.borderStrong),
            boxShadow: CoolShadows.clay(theme.brightness, strength: 0.55),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formattedDeparture,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  if (statusLabel != null)
                    _SignalChip(
                      icon: Icons.bolt_rounded,
                      label: statusLabel!,
                      color: effectiveStatusColor,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _RouteBlock(
                palette: palette,
                label: 'FROM',
                location: fromLocation,
                dotColor: palette.accent,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 9),
                child: Container(
                  width: 2,
                  height: 16,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _RouteBlock(
                palette: palette,
                label: 'TO',
                location: toLocation,
                dotColor: palette.orange,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DetailChip(
                    icon: Icons.local_shipping_outlined,
                    label: vehicleType,
                  ),
                  if (seats != null)
                    _DetailChip(
                      icon: Icons.event_seat_outlined,
                      label: '$seats seat${seats == 1 ? '' : 's'}',
                    ),
                  if (_distanceLabel != null)
                    _DetailChip(
                      icon: Icons.near_me_rounded,
                      label: _distanceLabel!,
                    ),
                  if (demandLabel != null)
                    _DetailChip(
                      icon: Icons.schedule_send_rounded,
                      label: demandLabel!,
                      foregroundColor: effectiveDemandColor,
                      backgroundColor: effectiveDemandColor.withValues(
                        alpha: 0.12,
                      ),
                      borderColor: effectiveDemandColor.withValues(alpha: 0.22),
                    ),
                  if (isReturn || isDriverReturnTrip)
                    _DetailChip(
                      icon: Icons.repeat_rounded,
                      label: context.l10n.returnKey,
                      foregroundColor: palette.purple,
                      backgroundColor: palette.purple.withValues(alpha: 0.12),
                      borderColor: palette.purple.withValues(alpha: 0.22),
                    ),
                  if (isRecurring)
                    _DetailChip(
                      icon: Icons.update_rounded,
                      label: context.l10n.repeat,
                      foregroundColor: palette.accent,
                      backgroundColor: palette.accentGlow,
                      borderColor: palette.accent.withValues(alpha: 0.18),
                    ),
                ],
              ),
              if (priceNote?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: palette.text3,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          priceNote!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteBlock extends StatelessWidget {
  const _RouteBlock({
    required this.palette,
    required this.label,
    required this.location,
    required this.dotColor,
  });

  final CoolPalette palette;
  final String label;
  final String location;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: palette.text3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
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

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  final IconData icon;
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final theme = Theme.of(context);
    final bg = backgroundColor ?? palette.surface3;
    final fg = foregroundColor ?? palette.text2;
    final border = borderColor ?? palette.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
