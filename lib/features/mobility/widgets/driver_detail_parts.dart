part of '../screens/driver_detail_screens.dart';

class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({required this.vehicle, required this.onEdit});

  final VehicleData vehicle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final statusColor = vehicle.statusColor(context);
    final summaryLine = vehicle.hasPlateNumber
        ? 'Plate ${vehicle.plateNumber}'
        : 'Plate number missing';

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: statusColor.withValues(alpha: 0.34),
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.18),
                  ),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  tripVehicleIcon(vehicle.type),
                  width: 32,
                  height: 32,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.type,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summaryLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(label: vehicle.status, color: statusColor),
            ],
          ),
          if (vehicle.hasBaseLocation) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: colors.tertiaryText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vehicle.baseLocation,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          CoolButton(
            label: 'Edit vehicle info',
            icon: Icons.edit_outlined,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class _VehicleReadinessCard extends StatelessWidget {
  const _VehicleReadinessCard({required this.vehicle});

  final VehicleData vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final statusColor = vehicle.statusColor(context);
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posting readiness',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Riders see these before',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _VehicleReadinessRow(
            label: 'Vehicle type',
            value: vehicle.type,
            isReady: vehicle.hasType,
          ),
          Divider(color: colors.divider, height: 20),
          _VehicleReadinessRow(
            label: 'Plate number',
            value: vehicle.hasPlateNumber
                ? vehicle.plateNumber
                : 'Add plate number',
            isReady: vehicle.hasPlateNumber,
          ),
          Divider(color: colors.divider, height: 20),
          _VehicleReadinessRow(
            label: 'Base location',
            value: vehicle.hasBaseLocation
                ? vehicle.baseLocation
                : 'Add base location',
            isReady: vehicle.hasBaseLocation,
          ),
          Divider(color: colors.divider, height: 20),
          _VehicleReadinessRow(
            label: 'Verification',
            value: vehicle.status,
            isReady: vehicle.isVerified,
            valueColor: statusColor,
          ),
        ],
      ),
    );
  }
}

class _VehicleReadinessRow extends StatelessWidget {
  const _VehicleReadinessRow({
    required this.label,
    required this.value,
    required this.isReady,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isReady;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final accent = valueColor ?? (isReady ? colors.success : colors.warning);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isReady ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 18,
          color: accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: valueColor ?? colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubscriptionAccessCard extends StatelessWidget {
  const _SubscriptionAccessCard({
    required this.activeSubscription,
    required this.latestSubscription,
    required this.freeTripsRemaining,
    required this.tripsUsedThisMonth,
    required this.hasExpiredSubscription,
  });

  final DriverSubscription? activeSubscription;
  final DriverSubscription? latestSubscription;
  final int freeTripsRemaining;
  final int tripsUsedThisMonth;
  final bool hasExpiredSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final stateColor = _subscriptionStateColor(
      context,
      activeSubscription: activeSubscription,
      freeTripsRemaining: freeTripsRemaining,
      hasExpiredSubscription: hasExpiredSubscription,
    );
    final planLabel =
        activeSubscription?.plan.displayName ??
        latestSubscription?.plan.displayName ??
        'Free tier';

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: stateColor.withValues(alpha: 0.34),
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current access',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subscriptionAccessMessage(
                        activeSubscription: activeSubscription,
                        freeTripsRemaining: freeTripsRemaining,
                        hasExpiredSubscription: hasExpiredSubscription,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusChip(
                label: _subscriptionStateLabel(
                  activeSubscription: activeSubscription,
                  freeTripsRemaining: freeTripsRemaining,
                  hasExpiredSubscription: hasExpiredSubscription,
                ),
                color: stateColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DriverStatBox(
                  label: 'Plan',
                  value: planLabel,
                  valueColor: colors.primaryText,
                  isMonospace: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: 'Credits',
                  value: activeSubscription != null
                      ? 'Unlimited'
                      : '$freeTripsRemaining',
                  valueColor: activeSubscription != null
                      ? colors.success
                      : freeTripsRemaining > 0
                      ? colors.warning
                      : colors.danger,
                  isMonospace: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: 'This month',
                  value: '$tripsUsedThisMonth',
                  valueColor: colors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverDetailNoteCard extends StatelessWidget {
  const _DriverDetailNoteCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: accentColor.withValues(alpha: 0.3),
      useGradient: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
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

class _DriverDetailIntroCard extends StatelessWidget {
  const _DriverDetailIntroCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
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

String _vehicleVerificationLabel(String? rawStatus) {
  return switch (rawStatus?.trim().toLowerCase()) {
    'verified' => 'Verified',
    'approved' => 'Approved',
    'pending_review' => 'Pending Review',
    'maintenance' => 'Maintenance',
    null || '' => 'Pending Review',
    final value =>
      value
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
  };
}

String _subscriptionStateLabel({
  required DriverSubscription? activeSubscription,
  required int freeTripsRemaining,
  required bool hasExpiredSubscription,
}) {
  if (activeSubscription != null) {
    return 'Active';
  }
  if (hasExpiredSubscription) {
    return 'Expired';
  }
  if (freeTripsRemaining <= 0) {
    return 'No credits';
  }
  if (freeTripsRemaining < 5) {
    return 'Low credits';
  }
  return 'Free tier';
}

Color _subscriptionStateColor(
  BuildContext context, {
  required DriverSubscription? activeSubscription,
  required int freeTripsRemaining,
  required bool hasExpiredSubscription,
}) {
  final colors = context.coolSemanticColors;
  if (activeSubscription != null) {
    return colors.success;
  }
  if (hasExpiredSubscription || freeTripsRemaining <= 0) {
    return colors.danger;
  }
  if (freeTripsRemaining < 5) {
    return colors.warning;
  }
  return colors.info;
}

String _subscriptionAccessMessage({
  required DriverSubscription? activeSubscription,
  required int freeTripsRemaining,
  required bool hasExpiredSubscription,
}) {
  if (activeSubscription != null) {
    return 'Unlimited trip posting is active until ${formatDate(activeSubscription.expiresAt)}.';
  }
  if (hasExpiredSubscription) {
    return 'Previous plan expired. Resubscribe below.';
  }
  if (freeTripsRemaining <= 0) {
    return 'Free credits used. Subscribe to keep posting.';
  }
  if (freeTripsRemaining < 5) {
    return 'Credits running low. Upgrade soon.';
  }
  return 'Free credits available. Upgrade anytime.';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _DriverDetailErrorState extends StatelessWidget {
  const _DriverDetailErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 40, color: colors.warning),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: CoolButton(
                label: 'Retry',
                variant: CoolButtonVariant.secondary,
                onTap: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
