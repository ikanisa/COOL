import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/cool_skeleton.dart';
import 'package:intl/intl.dart';

import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/trip.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';

enum _DriverProfileView { overview, manage }

/// Driver profile for mobility partners.
///
/// Wired to [driverProvider] for profile, subscription, and trip data.
/// The local [_DriverProfileData] display model maps from provider state.
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
    final currentVehicle = _VehicleData(
      type: profile?.vehicleType ?? 'Moto Taxi',
      plateNumber: profile?.vehicleDescription ?? '',
      baseLocation: profile?.isRegularDriver == true ? 'Regular' : 'Occasional',
      status: profile?.isOnline == true ? 'Online' : 'Offline',
    );
    final updatedVehicle = await showModalBottomSheet<_VehicleData>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EditVehicleSheet(vehicle: currentVehicle),
    );

    if (!mounted || updatedVehicle == null) return;

    // Persist vehicle update to backend.
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

    // Show a loading spinner if we have no profile yet.
    if (driverState.isLoading && profile == null) {
      return const CoolScreenScaffold(
        title: 'Driver',
        child: CoolSkeletonList(itemCount: 4),
      );
    }

    // Error state — profile failed to load.
    if (driverState.error != null && profile == null) {
      return CoolScreenScaffold(
        title: 'Driver',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.orange),
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

    // Map provider data to local display model.
    final vehicle = _VehicleData(
      type: profile?.vehicleType ?? currentUser?.vehicleType ?? 'Moto Taxi',
      plateNumber: _displayValue(profile?.vehicleDescription),
      baseLocation: profile?.isRegularDriver == true ? 'Regular' : 'Occasional',
      status: profile?.isOnline == true ? 'Online' : 'Offline',
    );

    final driver = _DriverProfileData(
      name: profile?.fullName ?? currentUser?.fullName ?? 'Driver',
      driverId: '#${_shortDriverId(profile?.userId ?? currentUser?.id)}',
      rating: profile?.rating ?? 0,
      tripsDone: scheduledTrips.length,
      freeTripsRemaining: profile?.credits ?? sub?.tripsRemaining ?? 0,
      tripsUsedThisMonth: driverState.tripsUsed,
      isOnline: profile?.isOnline ?? false,
      vehicle: vehicle,
      scheduledTrips: scheduledTrips
          .map(_ScheduledTripData.fromTrip)
          .toList(growable: false),
      subscription: sub != null && sub.isSubscribed
          ? _DriverSubscription(
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
          _DriverViewSwitcher(
            activeView: _activeView,
            onChanged: (view) {
              setState(() => _activeView = view);
            },
          ),
          const SizedBox(height: 18),
          if (_activeView == _DriverProfileView.overview) ...[
            _DriverAvailabilityCard(
              vehicleType: driver.vehicle.type,
              isOnline: driver.isOnline,
              onChanged: (value) => _toggleOnlineStatus(value),
            ),
            const SizedBox(height: 16),
            _DriverStatsCard(driver: driver),
            const SizedBox(height: 16),
            if (activeSubscription != null)
              _ActiveSubscriptionCard(
                subscription: activeSubscription,
                now: now,
              )
            else
              _DriverSubscriptionSummaryCard(
                freeTripsRemaining: driver.freeTripsRemaining,
                tripsUsedThisMonth: driver.tripsUsedThisMonth,
                showUpgradeHint: shouldShowUpgradeBanner,
                onOpenManage: () {
                  setState(() => _activeView = _DriverProfileView.manage);
                },
              ),
            const SizedBox(height: 18),
            SectionTitle(
              title: todaysTrips.isNotEmpty
                  ? 'Today\'s trips'
                  : 'Upcoming trips',
            ),
            const SizedBox(height: 10),
            _ScheduledTripsCard(trips: visibleTrips),
            const SizedBox(height: 12),
            CoolButton(
              label: 'Add return trip',
              variant: CoolButtonVariant.secondary,
              onTap: () => context.push('/mobility/schedule?role=driver'),
            ),
          ] else ...[
            SectionTitle(
              title: 'Vehicle',
              actionLabel: 'Edit',
              onAction: _openVehicleEditor,
            ),
            const SizedBox(height: 10),
            _VehicleInfoCard(vehicle: driver.vehicle),
            const SizedBox(height: 18),
            const SectionTitle(title: 'Subscription'),
            const SizedBox(height: 10),
            if (activeSubscription != null)
              _ActiveSubscriptionCard(
                subscription: activeSubscription,
                now: now,
              )
            else if (shouldShowUpgradeBanner)
              _SubscriptionBanner(
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
              _DriverSubscriptionSummaryCard(
                freeTripsRemaining: driver.freeTripsRemaining,
                tripsUsedThisMonth: driver.tripsUsedThisMonth,
                showUpgradeHint: false,
              ),
          ],
        ],
      ),
    );
  }
}

class _DriverViewSwitcher extends StatelessWidget {
  const _DriverViewSwitcher({
    required this.activeView,
    required this.onChanged,
  });

  final _DriverProfileView activeView;
  final ValueChanged<_DriverProfileView> onChanged;

  static const _items = [
    (_DriverProfileView.overview, 'Overview'),
    (_DriverProfileView.manage, 'Manage'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activeView == item.$1
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.$2,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: activeView == item.$1
                          ? Colors.black
                          : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverStatsCard extends StatelessWidget {
  const _DriverStatsCard({required this.driver});

  final _DriverProfileData driver;

  @override
  Widget build(BuildContext context) {
    final hasUnlimitedTrips = driver.subscription != null;
    final isLowOnTrips = !hasUnlimitedTrips && driver.freeTripsRemaining < 5;

    return CoolCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.accent, AppColors.blue],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  driver.initials,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.surface,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Driver ${driver.driverId}',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
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
                  color:
                      (driver.isOnline ? AppColors.accent : AppColors.surface3)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (driver.isOnline ? AppColors.accent : AppColors.border)
                            .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 15,
                      color: driver.isOnline
                          ? AppColors.accent
                          : AppColors.text3,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      driver.isOnline ? 'Online' : 'Offline',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: driver.isOnline
                            ? AppColors.accent
                            : AppColors.text2,
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
                child: _StatBox(
                  label: 'Trips Posted',
                  value: '${driver.tripsDone}',
                  valueColor: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBox(
                  label: 'Mobility Credits',
                  value: hasUnlimitedTrips
                      ? 'Unlimited'
                      : '${driver.freeTripsRemaining}',
                  valueColor: AppColors.yellow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBox(
                  label: 'Status',
                  value: hasUnlimitedTrips
                      ? 'Subscribed'
                      : (isLowOnTrips ? 'Low' : 'Ready'),
                  valueColor: isLowOnTrips
                      ? AppColors.orange
                      : AppColors.accent,
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

class _DriverSubscriptionSummaryCard extends StatelessWidget {
  const _DriverSubscriptionSummaryCard({
    required this.freeTripsRemaining,
    required this.tripsUsedThisMonth,
    required this.showUpgradeHint,
    this.onOpenManage,
  });

  final int freeTripsRemaining;
  final int tripsUsedThisMonth;
  final bool showUpgradeHint;
  final VoidCallback? onOpenManage;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$freeTripsRemaining credits left · $tripsUsedThisMonth posted this month.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.4,
                  ),
                ),
                if (showUpgradeHint && onOpenManage != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenManage,
                    child: const Text('Open subscription options'),
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

class _StatBox extends StatelessWidget {
  const _StatBox({
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (isMonospace ? GoogleFonts.dmMono : GoogleFonts.dmSans)(
              fontSize: 16,
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

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({
    required this.tripsUsedCount,
    required this.freeTripsRemaining,
    required this.selectedPlan,
    required this.isLoading,
    required this.onPlanSelected,
    required this.onPayTap,
  });

  final int tripsUsedCount;
  final int freeTripsRemaining;
  final SubscriptionPlan selectedPlan;
  final bool isLoading;
  final ValueChanged<SubscriptionPlan> onPlanSelected;
  final VoidCallback onPayTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      borderColor: AppColors.blue.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock Unlimited Trips',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$tripsUsedCount trips posted · $freeTripsRemaining credits remaining.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PlanCard(
                  plan: MomoService.motoTaxiPlan,
                  isSelected: selectedPlan == MomoService.motoTaxiPlan,
                  isFeatured: false,
                  onTap: () => onPlanSelected(MomoService.motoTaxiPlan),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlanCard(
                  plan: MomoService.cabOtherPlan,
                  isSelected: selectedPlan == MomoService.cabOtherPlan,
                  isFeatured: true,
                  onTap: () => onPlanSelected(MomoService.cabOtherPlan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CoolButton(
            label: 'Pay via MOMO USSD',
            isLoading: isLoading,
            onTap: onPayTap,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isFeatured,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isFeatured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppColors.accent
        : isFeatured
        ? AppColors.blue
        : AppColors.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentGlow
              : AppColors.surface2.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected || isFeatured ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(IconMapper.from(plan.emoji), size: 24, color: AppColors.text2),
            const SizedBox(height: 8),
            Text(
              plan.displayName,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatAmount(plan.amountRwf)} RWF',
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.accent : AppColors.blue,
              ),
            ),
            Text(
              '/month',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSubscriptionCard extends StatelessWidget {
  const _ActiveSubscriptionCard({
    required this.subscription,
    required this.now,
  });

  final _DriverSubscription subscription;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final totalDays = subscription.expiresAt
        .difference(subscription.startedAt)
        .inDays
        .clamp(1, 365);
    final daysRemaining = subscription.expiresAt
        .difference(now)
        .inDays
        .clamp(0, totalDays);
    final progress = daysRemaining / totalDays;

    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentGlow, AppColors.surface2],
      ),
      borderColor: AppColors.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.plan.displayName,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatAmount(subscription.plan.amountRwf)} RWF · '
                      'Expires ${_formatDate(subscription.expiresAt)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$daysRemaining days remaining',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.surface3,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoCard extends StatelessWidget {
  const _VehicleInfoCard({required this.vehicle});

  final _VehicleData vehicle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          _VehicleInfoTile(
            label: 'Vehicle Type',
            value: vehicle.type,
          ),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(label: 'Description', value: vehicle.plateNumber),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(label: 'Driver Type', value: vehicle.baseLocation),
          const Divider(color: AppColors.border, height: 1),
          _VehicleInfoTile(
            label: 'Availability',
            value: vehicle.status,
            valueColor: vehicle.statusColor,
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoTile extends StatelessWidget {
  const _VehicleInfoTile({
    required this.label,
    required this.value,
    this.valueColor = AppColors.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ),
    );
  }
}

class _DriverAvailabilityCard extends StatelessWidget {
  const _DriverAvailabilityCard({
    required this.vehicleType,
    required this.isOnline,
    required this.onChanged,
  });

  final String vehicleType;
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: isOnline ? AppColors.accent.withValues(alpha: 0.35) : null,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(_tripVehicleIcon(vehicleType), size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver Mode',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleType,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              _DriverModeToggle(value: isOnline, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isOnline ? AppColors.accentGlow : AppColors.surface3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOnline ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.accent : AppColors.text3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isOnline
                        ? 'Online — visible nearby.'
                        : 'Offline — toggle to go live.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isOnline ? AppColors.accent : AppColors.text2,
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

class _DriverModeToggle extends StatelessWidget {
  const _DriverModeToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 52,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.text,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _ScheduledTripsCard extends StatelessWidget {
  const _ScheduledTripsCard({required this.trips});

  final List<_ScheduledTripData> trips;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return CoolCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No scheduled trips yet.',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ),
        ),
      );
    }

    return CoolCard(
      child: Column(
        children: [
          for (var index = 0; index < trips.length; index++) ...[
            _ScheduledTripTile(trip: trips[index]),
            if (index != trips.length - 1)
              const Divider(color: AppColors.border, height: 1),
          ],
        ],
      ),
    );
  }
}

class _ScheduledTripTile extends StatelessWidget {
  const _ScheduledTripTile({required this.trip});

  final _ScheduledTripData trip;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      trip.vehicleLabel,
      if (trip.isReturnTrip) 'Return',
      if (trip.isRecurring) 'Daily',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              _tripVehicleIcon(trip.vehicleLabel),
              size: 21,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip.fromLocation} → ${trip.toLocation}',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTripDate(trip.departureTime),
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in chips)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: chip == 'Return'
                              ? AppColors.blueGlow
                              : AppColors.surface3,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          chip,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: chip == 'Return'
                                ? AppColors.blue
                                : AppColors.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditVehicleSheet extends StatefulWidget {
  const _EditVehicleSheet({required this.vehicle});

  final _VehicleData vehicle;

  @override
  State<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<_EditVehicleSheet> {
  late final TextEditingController _vehicleTypeController;
  late final TextEditingController _plateNumberController;
  late final TextEditingController _baseLocationController;
  late String _status;

  static const _statuses = ['Verified', 'Pending Review', 'Maintenance'];

  @override
  void initState() {
    super.initState();
    _vehicleTypeController = TextEditingController(text: widget.vehicle.type);
    _plateNumberController = TextEditingController(
      text: widget.vehicle.plateNumber,
    );
    _baseLocationController = TextEditingController(
      text: widget.vehicle.baseLocation,
    );
    _status = widget.vehicle.status;
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _plateNumberController.dispose();
    _baseLocationController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _VehicleData(
        type: _vehicleTypeController.text.trim(),
        plateNumber: _plateNumberController.text.trim(),
        baseLocation: _baseLocationController.text.trim(),
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Edit Vehicle',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),
              CoolTextField(
                label: 'Vehicle Type',
                hint: 'Moto Taxi',
                controller: _vehicleTypeController,
                prefixEmoji: '🛺',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              CoolTextField(
                label: 'Plate Number',
                hint: 'RAB 123 C',
                controller: _plateNumberController,
                prefixEmoji: '🔢',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              CoolTextField(
                label: 'Base Location',
                hint: 'Nyamirambo, Kigali',
                controller: _baseLocationController,
                prefixEmoji: '📍',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              Text(
                'Status',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _statuses)
                    _VehicleStatusChip(
                      label: option,
                      isSelected: _status == option,
                      onTap: () => setState(() => _status = option),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              CoolButton(label: 'Save Vehicle Info', onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleStatusChip extends StatelessWidget {
  const _VehicleStatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _DriverProfileData {
  const _DriverProfileData({
    required this.name,
    required this.driverId,
    required this.rating,
    required this.tripsDone,
    required this.freeTripsRemaining,
    required this.tripsUsedThisMonth,
    required this.isOnline,
    required this.vehicle,
    required this.scheduledTrips,
    this.subscription,
  });

  final String name;
  final String driverId;
  final double rating;
  final int tripsDone;
  final int freeTripsRemaining;
  final int tripsUsedThisMonth;
  final bool isOnline;
  final _VehicleData vehicle;
  final List<_ScheduledTripData> scheduledTrips;
  final _DriverSubscription? subscription;

  String get initials {
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  _DriverSubscription? activeSubscription(DateTime now) {
    if (subscription == null) return null;
    if (subscription!.expiresAt.isAfter(now)) return subscription;
    return null;
  }

  bool shouldShowUpgradeBanner(DateTime now) {
    final hasExpiredSubscription =
        subscription != null && !subscription!.expiresAt.isAfter(now);
    return hasExpiredSubscription || freeTripsRemaining < 5;
  }

  _DriverProfileData copyWith({_VehicleData? vehicle, bool? isOnline}) {
    return _DriverProfileData(
      name: name,
      driverId: driverId,
      rating: rating,
      tripsDone: tripsDone,
      freeTripsRemaining: freeTripsRemaining,
      tripsUsedThisMonth: tripsUsedThisMonth,
      isOnline: isOnline ?? this.isOnline,
      vehicle: vehicle ?? this.vehicle,
      scheduledTrips: scheduledTrips,
      subscription: subscription,
    );
  }
}

class _VehicleData {
  const _VehicleData({
    required this.type,
    required this.plateNumber,
    required this.baseLocation,
    required this.status,
  });

  final String type;
  final String plateNumber;
  final String baseLocation;
  final String status;

  String get emoji {
    final normalized = type.toLowerCase();
    if (normalized.contains('moto')) return '🛺';
    if (normalized.contains('cab')) return '🚗';
    if (normalized.contains('truck')) return '🚛';
    if (normalized.contains('liffan') || normalized.contains('van')) {
      return '🚐';
    }
    return '🚘';
  }

  Color get statusColor {
    final normalized = status.toLowerCase();
    if (normalized.contains('online') ||
        normalized.contains('verified') ||
        normalized.contains('active')) {
      return AppColors.accent;
    }
    if (normalized.contains('offline')) {
      return AppColors.text3;
    }
    if (normalized.contains('pending')) return AppColors.yellow;
    if (normalized.contains('maintenance')) return AppColors.orange;
    return AppColors.text;
  }
}

class _ScheduledTripData {
  const _ScheduledTripData({
    required this.fromLocation,
    required this.toLocation,
    required this.departureTime,
    required this.vehicleLabel,
    this.isReturnTrip = false,
    this.isRecurring = false,
  });

  final String fromLocation;
  final String toLocation;
  final DateTime departureTime;
  final String vehicleLabel;
  final bool isReturnTrip;
  final bool isRecurring;

  factory _ScheduledTripData.fromTrip(Trip trip) {
    return _ScheduledTripData(
      fromLocation: trip.fromLocation,
      toLocation: trip.toLocation,
      departureTime: trip.departureTime,
      vehicleLabel: trip.vehicleType,
      isReturnTrip: trip.isReturn || trip.isDriverReturnTrip,
      isRecurring: trip.isRecurring,
    );
  }
}

class _DriverSubscription {
  const _DriverSubscription({
    required this.plan,
    required this.startedAt,
    required this.expiresAt,
  });

  final SubscriptionPlan plan;
  final DateTime startedAt;
  final DateTime expiresAt;
}

String _formatAmount(int amount) {
  return NumberFormat.decimalPattern('en_US').format(amount);
}

String _formatDate(DateTime date) {
  return DateFormat('d MMM yyyy').format(date);
}

String _formatTripDate(DateTime date) {
  return DateFormat('EEE d MMM · HH:mm').format(date);
}

String _shortDriverId(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) {
    return '------';
  }
  return raw.length <= 6 ? raw : raw.substring(0, 6);
}

String _displayValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? '--' : trimmed;
}

IconData _tripVehicleIcon(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return Icons.two_wheeler_rounded;
  if (normalized.contains('cab')) return Icons.directions_car_rounded;
  if (normalized.contains('truck')) return Icons.local_shipping_rounded;
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return Icons.airport_shuttle_rounded;
  }
  return Icons.directions_car_filled_rounded;
}
