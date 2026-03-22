import 'package:flutter/material.dart';

import '../../core/identity/public_user_identity.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

import 'wa_button.dart';

/// Premium mobility listing for a driver with trust, proximity, and CTA hierarchy.
class DriverCard extends StatelessWidget {
  const DriverCard({
    required this.driverId,
    required this.displayName,
    required this.vehicleType,
    required this.distanceKm,
    required this.isOnline,
    required this.onWhatsAppTap,
    this.onTap,
    this.rating,
    this.tripCount,
    this.scheduledRoute,
    this.baseLocation,
    this.vehicleStatus,
    this.isRegularDriver = false,
    super.key,
  });

  final String driverId;
  final String displayName;
  final String vehicleType;
  final double distanceKm;
  final bool isOnline;
  final VoidCallback onWhatsAppTap;
  final VoidCallback? onTap;
  final double? rating;
  final int? tripCount;
  final String? scheduledRoute;
  final String? baseLocation;
  final String? vehicleStatus;
  final bool isRegularDriver;

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
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} m away';
    }
    return '${distanceKm.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final name = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: driverId,
    );
    final availabilityLabel = isOnline ? 'Live now' : 'Recently active';
    final trustLabel = isRegularDriver ? 'Trusted regular' : 'Verified listing';
    final routeSummary = scheduledRoute?.trim();
    final area = baseLocation?.trim();

    final content = Semantics(
      label:
          '$name. $vehicleType. $_distanceLabel. $availabilityLabel. $trustLabel.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.proximitySurface,
          gradient: colors.surfaceGradient,
          borderRadius: BorderRadius.circular(CoolRadii.lg),
          border: Border.all(
            color: isOnline
                ? palette.accent.withValues(alpha: 0.32)
                : colors.borderStrong,
          ),
          boxShadow: CoolShadows.clay(theme.brightness, strength: 0.55),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  initials: _initials,
                  isOnline: isOnline,
                  palette: palette,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(
                            label: availabilityLabel,
                            foregroundColor: isOnline
                                ? palette.accent
                                : palette.text2,
                            backgroundColor: isOnline
                                ? palette.accentGlow
                                : palette.surface3,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vehicleType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(icon: Icons.near_me_rounded, label: _distanceLabel),
                if (rating != null)
                  _MetricChip(
                    icon: Icons.star_rounded,
                    label: '${rating!.toStringAsFixed(1)} rating',
                    accentColor: palette.yellow,
                  ),
                if (tripCount != null && tripCount! > 0)
                  _MetricChip(
                    icon: Icons.route_rounded,
                    label: '$tripCount trips',
                    accentColor: palette.blue,
                  ),
                _MetricChip(
                  icon: Icons.verified_user_outlined,
                  label: trustLabel,
                  accentColor: palette.accent,
                ),
              ],
            ),
            if ((routeSummary?.isNotEmpty ?? false) ||
                (area?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (routeSummary?.isNotEmpty ?? false)
                      _DetailLine(
                        icon: Icons.alt_route_rounded,
                        label: 'Current route',
                        value: routeSummary!,
                      ),
                    if ((routeSummary?.isNotEmpty ?? false) &&
                        (area?.isNotEmpty ?? false))
                      const SizedBox(height: 10),
                    if (area?.isNotEmpty ?? false)
                      _DetailLine(
                        icon: Icons.place_outlined,
                        label: 'Base area',
                        value: area!,
                      ),
                    if ((vehicleStatus?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 10),
                      _DetailLine(
                        icon: Icons.info_outline_rounded,
                        label: 'Vehicle status',
                        value: vehicleStatus!.trim(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: WaButton(
                    label: 'Contact Driver',
                    iconOnly: MediaQuery.sizeOf(context).width < 380,
                    fullWidth: true,
                    onTap: onWhatsAppTap,
                  ),
                ),
              ],
            ),
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

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.isOnline,
    required this.palette,
  });

  final String initials;
  final bool isOnline;
  final CoolPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.accentGlow, palette.blueGlow],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: palette.border2),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isOnline ? palette.accent : palette.orange,
                shape: BoxShape.circle,
                border: Border.all(color: palette.surface2, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final theme = Theme.of(context);
    final color = accentColor ?? palette.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surface3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: palette.text3),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.text2,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
