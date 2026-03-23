import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../widgets/driver_overview_widgets.dart';
import '../widgets/driver_profile_models.dart';
import '../widgets/driver_subscription_widgets.dart';
import '../widgets/driver_vehicle_trip_widgets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/driver_detail_parts.dart';

class DriverVehicleScreen extends ConsumerStatefulWidget {
  const DriverVehicleScreen({super.key});

  @override
  ConsumerState<DriverVehicleScreen> createState() =>
      _DriverVehicleScreenState();
}

class _DriverVehicleScreenState extends ConsumerState<DriverVehicleScreen> {
  Future<void> _openVehicleEditor() async {
    final driverState = ref.read(driverProvider);
    final profile = driverState.profile;
    final currentVehicle = VehicleData(
      type: profile?.vehicleType ?? 'Moto Taxi',
      plateNumber: profile?.plateNumber ?? profile?.vehicleDescription ?? '',
      baseLocation: profile?.baseLocation ?? '',
      status: _vehicleVerificationLabel(profile?.vehicleStatus),
    );
    final updatedVehicle = await showCoolBottomSheet<VehicleData>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => EditVehicleSheet(vehicle: currentVehicle),
    );

    if (!mounted || updatedVehicle == null) {
      return;
    }

    final updatedProfile = await ref
        .read(driverProvider.notifier)
        .updateVehicle(
          updatedVehicle.type,
          updatedVehicle.plateNumber,
          updatedVehicle.baseLocation,
        );

    if (!mounted) {
      return;
    }

    final error = ref.read(driverProvider).error;
    if (error != null) {
      CoolToast.error(context, error);
      return;
    }
    if (updatedProfile != null) {
      CoolToast.success(context, 'Vehicle details updated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final driverState = ref.watch(driverProvider);
    final profile = driverState.profile;

    if (driverState.isLoading && profile == null) {
      return CoolScreenScaffold(
        title: context.l10n.vehicle,
        child: const CoolSkeletonList(itemCount: 3),
      );
    }
    if (driverState.error != null && profile == null) {
      return CoolScreenScaffold(
        title: context.l10n.vehicle,
        child: _DriverDetailErrorState(
          message: driverState.error!,
          onRetry: () => ref.read(driverProvider.notifier).loadDriverProfile(),
        ),
      );
    }

    final vehicle = VehicleData(
      type: profile?.vehicleType ?? currentUser?.vehicleType ?? 'Moto Taxi',
      plateNumber: displayValue(
        profile?.plateNumber ?? profile?.vehicleDescription,
      ),
      baseLocation: displayValue(profile?.baseLocation),
      status: _vehicleVerificationLabel(profile?.vehicleStatus),
    );

    return CoolScreenScaffold(
      title: context.l10n.vehicle,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DriverDetailIntroCard(
            title: context.l10n.vehicleDetails,
            message: 'Keep vehicle details current.',
          ),
          const SizedBox(height: CoolSpace.x4),
          _VehicleSummaryCard(vehicle: vehicle, onEdit: _openVehicleEditor),
          const SizedBox(height: CoolSpace.x4),
          VehicleInfoCard(vehicle: vehicle),
          const SizedBox(height: CoolSpace.x4),
          _VehicleReadinessCard(vehicle: vehicle),
        ],
      ),
    );
  }
}

class DriverSubscriptionScreen extends ConsumerStatefulWidget {
  const DriverSubscriptionScreen({super.key});

  @override
  ConsumerState<DriverSubscriptionScreen> createState() =>
      _DriverSubscriptionScreenState();
}

class _DriverSubscriptionScreenState
    extends ConsumerState<DriverSubscriptionScreen> {
  SubscriptionPlan _selectedPlan = MomoService.motoTaxiPlan;
  bool _isLaunchingSubscription = false;

  Future<void> _paySubscription() async {
    if (_isLaunchingSubscription) {
      return;
    }

    setState(() => _isLaunchingSubscription = true);

    try {
      await ref
          .read(driverProvider.notifier)
          .initiateSubscription(_selectedPlan);

      if (!mounted) {
        return;
      }
      final error = ref.read(driverProvider).error;
      if (error != null) {
        CoolToast.error(context, error);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final currentUser = ref.watch(currentUserProvider);
    final driverState = ref.watch(driverProvider);
    final profile = driverState.profile;
    final sub = driverState.subscription;
    final now = DateTime.now();

    if (driverState.isLoading && profile == null) {
      return const CoolScreenScaffold(
        title: 'Subscription',
        child: CoolSkeletonList(itemCount: 3),
      );
    }
    if (driverState.error != null && profile == null) {
      return CoolScreenScaffold(
        title: 'Subscription',
        child: _DriverDetailErrorState(
          message: driverState.error!,
          onRetry: () => ref.read(driverProvider.notifier).loadDriverProfile(),
        ),
      );
    }

    final driver = DriverProfileData(
      name: profile?.fullName ?? currentUser?.displayUserId ?? '',
      driverId:
          '#${profile?.fullName ?? currentUser?.displayUserId ?? shortDriverId(profile?.userId ?? currentUser?.id)}',
      rating: profile?.rating ?? 0,
      tripsDone: driverState.scheduledTrips.length,
      freeTripsRemaining: profile?.credits ?? sub?.tripsRemaining ?? 0,
      tripsUsedThisMonth: driverState.tripsUsed,
      isOnline: profile?.isOnline ?? false,
      vehicle: VehicleData(
        type: profile?.vehicleType ?? currentUser?.vehicleType ?? 'Moto Taxi',
        plateNumber: displayValue(
          profile?.plateNumber ?? profile?.vehicleDescription,
        ),
        baseLocation: displayValue(profile?.baseLocation),
        status: _vehicleVerificationLabel(profile?.vehicleStatus),
      ),
      scheduledTrips: driverState.scheduledTrips
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
    final hasExpiredSubscription =
        driver.subscription != null && activeSubscription == null;

    return CoolScreenScaffold(
      title: 'Subscription',
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DriverDetailIntroCard(
            title: 'Subscription access',
            message: 'Credits and status.',
          ),
          const SizedBox(height: CoolSpace.x4),
          _SubscriptionAccessCard(
            activeSubscription: activeSubscription,
            latestSubscription: driver.subscription,
            freeTripsRemaining: driver.freeTripsRemaining,
            tripsUsedThisMonth: driver.tripsUsedThisMonth,
            hasExpiredSubscription: hasExpiredSubscription,
          ),
          const SizedBox(height: CoolSpace.x4),
          if (activeSubscription != null) ...[
            ActiveSubscriptionCard(subscription: activeSubscription, now: now),
            const SizedBox(height: CoolSpace.x4),
            _DriverDetailNoteCard(
              title: 'Renewal note',
              message:
                  'Active until ${formatDate(activeSubscription.expiresAt)}.',
              // ignore: unused_field
              icon: Icons.schedule_rounded,
              accentColor: colors.info,
            ),
          ] else ...[
            DriverSubscriptionBanner(
              tripsUsedCount: driver.tripsUsedThisMonth,
              freeTripsRemaining: driver.freeTripsRemaining,
              selectedPlan: _selectedPlan,
              isLoading: _isLaunchingSubscription,
              onPlanSelected: (plan) {
                setState(() => _selectedPlan = plan);
              },
              onPayTap: _paySubscription,
            ),
            const SizedBox(height: CoolSpace.x4),
            _DriverDetailNoteCard(
              title: 'Selected plan',
              message:
                  '${_selectedPlan.displayName} ${formatAmount(_selectedPlan.amountRwf)} RWF/month via USSD.',
              icon: Icons.phone_forwarded_rounded,
              accentColor: colors.accent,
            ),
          ],
        ],
      ),
    );
  }
}
