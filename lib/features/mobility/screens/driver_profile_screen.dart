import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../widgets/driver_overview_widgets.dart';
import '../widgets/driver_profile_models.dart';
import '../widgets/driver_subscription_widgets.dart';
import '../widgets/driver_vehicle_trip_widgets.dart';
import '../../../core/l10n/l10n.dart';

/// Driver profile for mobility partners.
///
/// Wired to [driverProvider] for profile, subscription, and trip data.
/// The local [DriverProfileData] display model maps from provider state.
class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(driverProvider.notifier).loadDriverProfile();
    });
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    final locationState = ref.read(mobilityLocationProvider);
    final position = locationState.position;
    if (position == null) {
      if (!mounted) return;
      CoolToast.error(
        context,
        'Location is required before changing driver mode.',
      );
      return;
    }

    await ref
        .read(driverProvider.notifier)
        .setOnlineStatus(
          isOnline: value,
          latitude: position.latitude,
          longitude: position.longitude,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final currentUser = ref.watch(currentUserProvider);
    final driverState = ref.watch(driverProvider);
    final profile = driverState.profile;
    final sub = driverState.subscription;
    final now = DateTime.now();
    final scheduledTrips = driverState.scheduledTrips;

    // Loading state.
    if (driverState.isLoading && profile == null) {
      return CoolScreenScaffold(
        title: context.l10n.driver,
        child: const CoolSkeletonList(itemCount: 4),
      );
    }

    // Error state.
    if (driverState.error != null && profile == null) {
      return CoolScreenScaffold(
        title: context.l10n.driver,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 40,
                  color: colors.warning,
                ),
                const SizedBox(height: CoolSpace.x4),
                Text(
                  driverState.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
                SizedBox(
                  width: 160,
                  child: CoolButton(
                    label: 'Retry',
                    variant: CoolButtonVariant.secondary,
                    semanticsLabel: context.l10n.retryLoadingDriverProfile,
                    onTap: () =>
                        ref.read(driverProvider.notifier).loadDriverProfile(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Build display model from provider state.
    final vehicle = VehicleData(
      type: profile?.vehicleType ?? currentUser?.vehicleType ?? 'Moto Taxi',
      plateNumber: displayValue(
        profile?.plateNumber ?? profile?.vehicleDescription,
      ),
      baseLocation: displayValue(profile?.baseLocation),
      status: _vehicleVerificationLabel(profile?.vehicleStatus),
    );

    final driver = DriverProfileData(
      name: profile?.fullName ?? currentUser?.displayUserId ?? '',
      driverId:
          '#${profile?.fullName ?? currentUser?.displayUserId ?? shortDriverId(profile?.userId ?? currentUser?.id)}',
      rating: profile?.rating ?? 0,
      tripsDone: scheduledTrips.length,
      freeTripsRemaining: profile?.credits ?? sub?.tripsRemaining ?? 0,
      tripsUsedThisMonth: driverState.tripsUsed,
      isOnline: profile?.isOnline ?? false,
      vehicle: vehicle,
      scheduledTrips: scheduledTrips
          .map(ScheduledTripData.fromTrip)
          .toList(growable: false),
      subscription: sub != null && sub.isSubscribed
          ? DriverSubscription(
              plan: sub.planId == 'cab_other'
                  ? SubscriptionPlan.cabOther
                  : SubscriptionPlan.moto,
              startedAt: sub.createdAt ?? now,
              expiresAt: sub.expiresAt ?? now.add(const Duration(days: 30)),
            )
          : null,
    );

    final activeSubscription = driver.activeSubscription(now);
    final shouldShowUpgradeBanner = driver.shouldShowUpgradeBanner(now);
    final todaysTrips = driver.scheduledTrips
        .where(
          (trip) =>
              trip.departureTime.year == now.year &&
              trip.departureTime.month == now.month &&
              trip.departureTime.day == now.day,
        )
        .toList(growable: false);
    final visibleTrips =
        (todaysTrips.isNotEmpty ? todaysTrips : driver.scheduledTrips.take(3))
            .toList(growable: false);

    return CoolScreenScaffold(
      title: context.l10n.driver,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DriverDashboardCard(
            driver: driver,
            planLabel:
                activeSubscription?.plan.displayName ?? 'Free driver plan',
            onAvailabilityChanged: _toggleOnlineStatus,
            onAddReturnTrip: () =>
                context.push('${AppRoutes.mobilitySchedule}?role=driver'),
            onOpenVehicle: () => context.push(AppRoutes.mobilityDriverVehicle),
            onOpenSubscription: () =>
                context.push(AppRoutes.mobilityDriverSubscription),
          ),
          const SizedBox(height: CoolSpace.x4),
          if (activeSubscription != null)
            ActiveSubscriptionCard(subscription: activeSubscription, now: now)
          else
            DriverSubscriptionSummaryCard(
              freeTripsRemaining: driver.freeTripsRemaining,
              tripsUsedThisMonth: driver.tripsUsedThisMonth,
              showUpgradeHint: shouldShowUpgradeBanner,
              onOpenManage: () =>
                  context.push(AppRoutes.mobilityDriverSubscription),
            ),
          const SizedBox(height: 18),
          _DriverSectionIntro(
            title: todaysTrips.isNotEmpty ? 'Today\'s trips' : 'Upcoming trips',
            subtitle: visibleTrips.isEmpty
                ? 'No trips posted yet.'
                : '',
          ),
          const SizedBox(height: 10),
          ScheduledTripsCard(trips: visibleTrips),
        ],
      ),
    );
  }

  String _vehicleVerificationLabel(String? rawStatus) {
    return switch (rawStatus?.trim().toLowerCase()) {
      'verified' => 'Verified',
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
}

class _DriverDashboardCard extends StatelessWidget {
  const _DriverDashboardCard({
    required this.driver,
    required this.planLabel,
    required this.onAvailabilityChanged,
    required this.onAddReturnTrip,
    required this.onOpenVehicle,
    required this.onOpenSubscription,
  });

  final DriverProfileData driver;
  final String planLabel;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onAddReturnTrip;
  final VoidCallback onOpenVehicle;
  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final creditsLabel = driver.subscription != null
        ? 'Unlimited'
        : '${driver.freeTripsRemaining} left';

    return CoolCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: colors.routeSurface,
      borderColor: driver.isOnline ? colors.accent : colors.borderStrong,
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
                      'Driver dashboard',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.tertiaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      driver.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      '${driver.vehicle.type} · Driver ${driver.driverId}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              DriverModeToggle(
                value: driver.isOnline,
                onChanged: onAvailabilityChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: driver.isOnline
                  ? colors.chipSelectedBackground
                  : colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(
                color: driver.isOnline ? colors.accent : colors.border,
              ),
            ),
            child: Text(
              driver.isOnline
                  ? 'Live — riders can see you.'
                  : 'Offline — go live to take requests.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: driver.isOnline
                    ? colors.primaryText
                    : colors.secondaryText,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DriverQuickStat(
                  label: 'Trips',
                  value: '${driver.tripsDone}',
                  valueColor: colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverQuickStat(
                  label: 'Credits',
                  value: creditsLabel,
                  valueColor: colors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverQuickStat(
                  label: 'Plan',
                  value: planLabel,
                  valueColor: colors.info,
                  isMonospace: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(label: 'Add return trip', onTap: onAddReturnTrip),
          const SizedBox(height: CoolSpace.x2),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: onOpenVehicle,
                child: Text(context.l10n.vehicle),
              ),
              TextButton(
                onPressed: onOpenSubscription,
                child: Text(context.l10n.subscription),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverQuickStat extends StatelessWidget {
  const _DriverQuickStat({
    required this.label,
    required this.value,
    required this.valueColor,
    this.isMonospace = true,
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
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
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

class _DriverSectionIntro extends StatelessWidget {
  const _DriverSectionIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
