import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

enum _DriverProfileView { overview, manage }

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
  SubscriptionPlan _selectedPlan = MomoService.motoTaxiPlan;
  bool _isLaunchingSubscription = false;
  _DriverProfileView _activeView = _DriverProfileView.overview;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(driverProvider.notifier).loadDriverProfile();
    });
  }

  Future<void> _openVehicleEditor() async {
    final driverState = ref.read(driverProvider);
    final profile = driverState.profile;
    final currentVehicle = VehicleData(
      type: profile?.vehicleType ?? 'Moto Taxi',
      plateNumber: profile?.plateNumber ?? profile?.vehicleDescription ?? '',
      baseLocation: profile?.baseLocation ?? '',
      status: _vehicleVerificationLabel(profile?.vehicleStatus),
    );
    final updatedVehicle = await showModalBottomSheet<VehicleData>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => EditVehicleSheet(vehicle: currentVehicle),
    );

    if (!mounted || updatedVehicle == null) return;

    await ref
        .read(driverProvider.notifier)
        .updateVehicle(
          updatedVehicle.type,
          updatedVehicle.plateNumber,
          updatedVehicle.baseLocation,
        );
  }

  Future<void> _paySubscription() async {
    if (_isLaunchingSubscription) return;

    setState(() => _isLaunchingSubscription = true);

    try {
      await ref
          .read(driverProvider.notifier)
          .initiateSubscription(_selectedPlan);

      if (!mounted) return;
      final error = ref.read(driverProvider).error;
      if (error != null) {
        CoolToast.error(context, error);
      }
    } catch (_) {
      if (!mounted) return;
      CoolToast.error(
        context,
        'Unable to open the USSD dialer. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunchingSubscription = false);
      }
    }
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
      return const CoolScreenScaffold(
        title: 'Driver',
        child: CoolSkeletonList(itemCount: 4),
      );
    }

    // Error state.
    if (driverState.error != null && profile == null) {
      return CoolScreenScaffold(
        title: 'Driver',
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
                GestureDetector(
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
              ],
            ),
          ),
        ),
      );
    }

    // Build display model from provider state.
    final vehicle = VehicleData(
      type: profile?.vehicleType ?? currentUser?.vehicleType ?? 'Moto Taxi',
      plateNumber: displayValue(profile?.plateNumber ?? profile?.vehicleDescription),
      baseLocation: displayValue(profile?.baseLocation),
      status: _vehicleVerificationLabel(profile?.vehicleStatus),
    );

    final driver = DriverProfileData(
      name: profile?.fullName ?? currentUser?.displayUserId ?? '000000',
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
      title: 'Driver',
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DriverViewSwitcher(
            activeIndex: _activeView.index,
            onChanged: (index) {
              setState(() => _activeView = _DriverProfileView.values[index]);
            },
          ),
          const SizedBox(height: 18),
          if (_activeView == _DriverProfileView.overview) ...[
            _DriverDashboardCard(
              driver: driver,
              planLabel:
                  activeSubscription?.plan.displayName ?? 'Free driver plan',
              onAvailabilityChanged: _toggleOnlineStatus,
              onAddReturnTrip: () =>
                  context.push('/mobility/schedule?role=driver'),
              onOpenManage: () {
                setState(() => _activeView = _DriverProfileView.manage);
              },
            ),
            const SizedBox(height: 16),
            if (activeSubscription != null)
              ActiveSubscriptionCard(subscription: activeSubscription, now: now)
            else
              DriverSubscriptionSummaryCard(
                freeTripsRemaining: driver.freeTripsRemaining,
                tripsUsedThisMonth: driver.tripsUsedThisMonth,
                showUpgradeHint: shouldShowUpgradeBanner,
                onOpenManage: () {
                  setState(() => _activeView = _DriverProfileView.manage);
                },
              ),
            const SizedBox(height: 18),
            _DriverSectionIntro(
              title: todaysTrips.isNotEmpty
                  ? 'Today\'s trips'
                  : 'Upcoming trips',
              subtitle: visibleTrips.isEmpty
                  ? 'Your next posted rides will show here.'
                  : 'Keep the next rides visible and current.',
            ),
            const SizedBox(height: 10),
            ScheduledTripsCard(trips: visibleTrips),
          ] else ...[
            _DriverManageSummaryCard(
              vehicle: driver.vehicle,
              planLabel:
                  activeSubscription?.plan.displayName ??
                  (shouldShowUpgradeBanner
                      ? 'Upgrade available'
                      : 'Free driver plan'),
              onEditVehicle: _openVehicleEditor,
            ),
            const SizedBox(height: 16),
            VehicleInfoCard(vehicle: driver.vehicle),
            const SizedBox(height: 16),
            if (activeSubscription != null)
              ActiveSubscriptionCard(subscription: activeSubscription, now: now)
            else if (shouldShowUpgradeBanner)
              DriverSubscriptionBanner(
                tripsUsedCount: driver.tripsUsedThisMonth,
                freeTripsRemaining: driver.freeTripsRemaining,
                selectedPlan: _selectedPlan,
                isLoading: _isLaunchingSubscription,
                onPlanSelected: (plan) {
                  setState(() => _selectedPlan = plan);
                },
                onPayTap: _paySubscription,
              )
            else
              DriverSubscriptionSummaryCard(
                freeTripsRemaining: driver.freeTripsRemaining,
                tripsUsedThisMonth: driver.tripsUsedThisMonth,
                showUpgradeHint: false,
              ),
          ],
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
      final value => value
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
    required this.onOpenManage,
  });

  final DriverProfileData driver;
  final String planLabel;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onAddReturnTrip;
  final VoidCallback onOpenManage;

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
                  ? 'Driver mode is live. Nearby riders can see you now.'
                  : 'Driver mode is off. Go live when you are ready to take requests.',
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpenManage,
              child: const Text('Manage vehicle and plan'),
            ),
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

class _DriverManageSummaryCard extends StatelessWidget {
  const _DriverManageSummaryCard({
    required this.vehicle,
    required this.planLabel,
    required this.onEditVehicle,
  });

  final VehicleData vehicle;
  final String planLabel;
  final VoidCallback onEditVehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle and plan',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keep your vehicle details current and review subscription access in one place.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEditVehicle,
                child: const Text('Edit vehicle'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DriverInfoPill(
                icon: tripVehicleIcon(vehicle.type),
                label: vehicle.type,
              ),
              _DriverInfoPill(
                icon: Icons.verified_rounded,
                label: planLabel,
                valueColor: AppColors.blue,
              ),
              _DriverInfoPill(
                icon: Icons.circle,
                label: vehicle.status,
                valueColor: vehicle.statusColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverInfoPill extends StatelessWidget {
  const _DriverInfoPill({
    required this.icon,
    required this.label,
    this.valueColor = AppColors.text2,
  });

  final IconData icon;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: valueColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
