import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
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
        child: CoolSkeletonList(itemCount: 4),
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
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 40,
                  color: AppColors.orange,
                ),
                const SizedBox(height: 16),
                Text(
                  driverState.error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: context.l10n.retryLoadingDriverProfile,
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(driverProvider.notifier).loadDriverProfile(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentGlow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Retry',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
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
          const SizedBox(height: 16),
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
    final creditsLabel = driver.subscription != null
        ? 'Unlimited'
        : '${driver.freeTripsRemaining} left';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: driver.isOnline
              ? AppColors.accent.withValues(alpha: 0.32)
              : AppColors.border,
        ),
      ),
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
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      driver.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${driver.vehicle.type} · Driver ${driver.driverId}',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
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
                  ? AppColors.accentGlow
                  : AppColors.surface3,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: driver.isOnline ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Text(
              driver.isOnline
                  ? 'Live — riders can see you.'
                  : 'Offline — go live to take requests.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: driver.isOnline ? AppColors.accent : AppColors.text2,
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
                  valueColor: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverQuickStat(
                  label: 'Credits',
                  value: creditsLabel,
                  valueColor: AppColors.yellow,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverQuickStat(
                  label: 'Plan',
                  value: planLabel,
                  valueColor: AppColors.blue,
                  isMonospace: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CoolButton(label: 'Add return trip', onTap: onAddReturnTrip),
          const SizedBox(height: 8),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: (isMonospace ? GoogleFonts.dmMono : GoogleFonts.dmSans)(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
        ),
      ],
    );
  }
}