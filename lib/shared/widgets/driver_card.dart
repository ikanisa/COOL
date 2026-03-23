import 'package:flutter/material.dart';

import '../../core/identity/public_user_identity.dart';
import '../../core/theme/cool_foundations.dart';

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
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final onlineColor = colors.demandLow;
    final offlineColor = colors.warning;
    final name = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: driverId,
    );
    final availabilityLabel = isOnline ? 'Live now' : 'Recently active';
    final trustLabel = isRegularDriver ? 'Trusted regular' : 'Verified listing';
    final routeSummary = scheduledRoute?.trim();
    final area = baseLocation?.trim();

    final content = Semantics(
      button: onTap != null,
      label:
          '$name. $vehicleType. $_distanceLabel. $availabilityLabel. $trustLabel.',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(space.x5),
        decoration: BoxDecoration(
          color: colors.proximitySurface,
          gradient: colors.surfaceGradient,
          borderRadius: BorderRadius.circular(radii.lg),
          border: Border.all(
            color: isOnline
                ? onlineColor.withValues(alpha: 0.32)
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
                  colors: colors,
                ),
                SizedBox(width: space.x3),
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
                                fontWeight: FontWeight.w800,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          SizedBox(width: space.x2),
                          _StatusBadge(
                            label: availabilityLabel,
                            foregroundColor: isOnline
                                ? onlineColor
                                : colors.secondaryText,
                            backgroundColor: isOnline
                                ? onlineColor.withValues(alpha: 0.14)
                                : colors.cardSurfaceStrong,
                          ),
                        ],
                      ),
                      SizedBox(height: space.x1 + 2),
                      Text(
                        vehicleType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: space.x3 + 2),
            Wrap(
              spacing: space.x2,
              runSpacing: space.x2,
              children: [
                _MetricChip(icon: Icons.near_me_rounded, label: _distanceLabel),
                if (rating != null)
                  _MetricChip(
                    icon: Icons.star_rounded,
                    label: '${rating!.toStringAsFixed(1)} rating',
                    accentColor: colors.warning,
                  ),
                if (tripCount != null && tripCount! > 0)
                  _MetricChip(
                    icon: Icons.route_rounded,
                    label: '$tripCount trips',
                    accentColor: colors.info,
                  ),
                _MetricChip(
                  icon: Icons.verified_user_outlined,
                  label: trustLabel,
                  accentColor: colors.accent,
                ),
              ],
            ),
            if ((routeSummary?.isNotEmpty ?? false) ||
                (area?.isNotEmpty ?? false)) ...[
              SizedBox(height: space.x3 + 2),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(space.x3),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.circular(radii.md),
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
                      SizedBox(height: space.x2),
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
            SizedBox(height: space.x3 + 2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, CoolTapTargets.comfortable),
                    ),
                  ),
                ),
                SizedBox(width: space.x2),
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
    required this.colors,
  });

  final String initials;
  final bool isOnline;
  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final statusColor = isOnline ? colors.demandLow : colors.warning;
    return SizedBox(
      width: CoolTapTargets.minimum + 2,
      height: CoolTapTargets.minimum + 2,
      child: Stack(
        children: [
          Container(
            width: CoolTapTargets.minimum + 2,
            height: CoolTapTargets.minimum + 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.accent.withValues(alpha: 0.18),
                  colors.info.withValues(alpha: 0.24),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
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
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: colors.proximitySurface, width: 2),
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
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
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
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final color = accentColor ?? colors.secondaryText;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: space.x1 + 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
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
    final space = context.coolSpace;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colors.tertiaryText),
        SizedBox(width: space.x2),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
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
