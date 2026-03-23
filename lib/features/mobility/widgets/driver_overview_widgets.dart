import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/tab_pill.dart';
import 'driver_profile_models.dart';

class DriverStatsCard extends StatelessWidget {
  const DriverStatsCard({required this.driver, super.key});

  final DriverProfileData driver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final hasUnlimitedTrips = driver.subscription != null;
    final isLowOnTrips = !hasUnlimitedTrips && driver.freeTripsRemaining < 5;

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: colors.accentGradient,
                ),
                alignment: Alignment.center,
                child: Text(
                  driver.initials,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.accentForeground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Driver ${driver.driverId}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: driver.isOnline
                      ? colors.chipSelectedBackground
                      : colors.chipBackground,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(
                    color: driver.isOnline ? colors.accent : colors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: driver.isOnline
                          ? colors.accent
                          : colors.tertiaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      driver.isOnline ? 'Online' : 'Offline',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: driver.isOnline
                            ? colors.primaryText
                            : colors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.tripsPosted,
                  value: '${driver.tripsDone}',
                  valueColor: colors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.mobilityCredits,
                  value: hasUnlimitedTrips
                      ? 'Unlimited'
                      : '${driver.freeTripsRemaining}',
                  valueColor: colors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.status,
                  value: hasUnlimitedTrips
                      ? 'Subscribed'
                      : (isLowOnTrips ? 'Low' : 'Ready'),
                  valueColor: isLowOnTrips ? colors.warning : colors.accent,
                  isMonospace: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DriverStatBox extends StatelessWidget {
  const DriverStatBox({
    required this.label,
    required this.value,
    required this.valueColor,
    this.isMonospace = true,
    super.key,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool isMonospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class DriverAvailabilityCard extends StatelessWidget {
  const DriverAvailabilityCard({
    required this.vehicleType,
    required this.isOnline,
    required this.onChanged,
    super.key,
  });

  final String vehicleType;
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: isOnline ? colors.accent : colors.borderStrong,
      useGradient: false,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.inputSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  tripVehicleIcon(vehicleType),
                  width: 22,
                  height: 22,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver mode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleType,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              DriverModeToggle(value: isOnline, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isOnline
                  ? colors.chipSelectedBackground
                  : colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(
                color: isOnline ? colors.accent : colors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isOnline ? colors.accent : colors.tertiaryText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isOnline
                        ? 'Online. Visible nearby.'
                        : 'Offline. Toggle to go live.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOnline
                          ? colors.primaryText
                          : colors.secondaryText,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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

class DriverModeToggle extends StatelessWidget {
  const DriverModeToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      toggled: value,
      label: value ? 'Driver mode on' : 'Driver mode off',
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: colors.accent,
        inactiveTrackColor: colors.chipBackground,
      ),
    );
  }
}

class DriverSubscriptionSummaryCard extends StatelessWidget {
  const DriverSubscriptionSummaryCard({
    required this.freeTripsRemaining,
    required this.tripsUsedThisMonth,
    required this.showUpgradeHint,
    this.onOpenManage,
    super.key,
  });

  final int freeTripsRemaining;
  final int tripsUsedThisMonth;
  final bool showUpgradeHint;
  final VoidCallback? onOpenManage;

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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.inputSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$freeTripsRemaining credits left. $tripsUsedThisMonth used this month.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (showUpgradeHint && onOpenManage != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenManage,
                    child: Text(context.l10n.openSubscriptionOptions),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DriverViewSwitcher extends StatelessWidget {
  const DriverViewSwitcher({
    required this.activeIndex,
    required this.onChanged,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;

  static const _labels = ['Overview', 'Manage'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            Expanded(
              child: TabPill(
                label: _labels[i],
                isActive: activeIndex == i,
                onTap: () => onChanged(i),
              ),
            ),
            if (i < _labels.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
