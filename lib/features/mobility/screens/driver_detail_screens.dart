import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
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
    final updatedVehicle = await showModalBottomSheet<VehicleData>(
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
      return const CoolScreenScaffold(
        title: 'Vehicle',
        child: CoolSkeletonList(itemCount: 3),
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
      title: 'Vehicle',
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DriverDetailIntroCard(
            title: 'Vehicle details',
            subtitle:
                'Keep your vehicle info',
          ),
          const SizedBox(height: 16),
          _VehicleSummaryCard(vehicle: vehicle, onEdit: _openVehicleEditor),
          const SizedBox(height: 16),
          VehicleInfoCard(vehicle: vehicle),
          const SizedBox(height: 16),
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
            subtitle:
                'Credits plan status and',
          ),
          const SizedBox(height: 16),
          _SubscriptionAccessCard(
            activeSubscription: activeSubscription,
            latestSubscription: driver.subscription,
            freeTripsRemaining: driver.freeTripsRemaining,
            tripsUsedThisMonth: driver.tripsUsedThisMonth,
            hasExpiredSubscription: hasExpiredSubscription,
          ),
          const SizedBox(height: 16),
          if (activeSubscription != null) ...[
            ActiveSubscriptionCard(subscription: activeSubscription, now: now),
            const SizedBox(height: 16),
            _DriverDetailNoteCard(
              title: 'Renewal note',
              message:
                  'Active until ${formatDate(activeSubscription.expiresAt)}.',
              // ignore: unused_field
              icon: Icons.schedule_rounded,
              accentColor: AppColors.blue,
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
            const SizedBox(height: 16),
            _DriverDetailNoteCard(
              title: 'Selected plan',
              message:
                  '${_selectedPlan.displayName} ${formatAmount(_selectedPlan.amountRwf)} RWF/month via',
              icon: Icons.phone_forwarded_rounded,
              accentColor: AppColors.accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({required this.vehicle, required this.onEdit});

  final VehicleData vehicle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final summaryLine = vehicle.hasPlateNumber
        ? 'Plate ${vehicle.plateNumber}'
        : 'Plate number missing';

    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          vehicle.statusColor.withValues(alpha: 0.14),
          AppColors.surface2,
        ],
      ),
      borderColor: vehicle.statusColor.withValues(alpha: 0.34),
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
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  tripVehicleIcon(vehicle.type),
                  width: 32,
                  height: 32,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.type,
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summaryLine,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(label: vehicle.status, color: vehicle.statusColor),
            ],
          ),
          if (vehicle.hasBaseLocation) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.text3,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vehicle.baseLocation,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
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
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posting readiness',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Riders see these before',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _VehicleReadinessRow(
            label: 'Vehicle type',
            value: vehicle.type,
            isReady: vehicle.hasType,
          ),
          Divider(color: AppColors.border, height: 20),
          _VehicleReadinessRow(
            label: 'Plate number',
            value: vehicle.hasPlateNumber
                ? vehicle.plateNumber
                : 'Add plate number',
            isReady: vehicle.hasPlateNumber,
          ),
          Divider(color: AppColors.border, height: 20),
          _VehicleReadinessRow(
            label: 'Base location',
            value: vehicle.hasBaseLocation
                ? vehicle.baseLocation
                : 'Add base location',
            isReady: vehicle.hasBaseLocation,
          ),
          Divider(color: AppColors.border, height: 20),
          _VehicleReadinessRow(
            label: 'Verification',
            value: vehicle.status,
            isReady: vehicle.isVerified,
            valueColor: vehicle.statusColor,
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
    final accent =
        valueColor ?? (isReady ? AppColors.accent : AppColors.orange);
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
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? AppColors.text2,
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
    final stateColor = _subscriptionStateColor(
      activeSubscription: activeSubscription,
      freeTripsRemaining: freeTripsRemaining,
      hasExpiredSubscription: hasExpiredSubscription,
    );
    final planLabel =
        activeSubscription?.plan.displayName ??
        latestSubscription?.plan.displayName ??
        'Free tier';

    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [stateColor.withValues(alpha: 0.12), AppColors.surface2],
      ),
      borderColor: stateColor.withValues(alpha: 0.34),
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
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subscriptionAccessMessage(
                        activeSubscription: activeSubscription,
                        freeTripsRemaining: freeTripsRemaining,
                        hasExpiredSubscription: hasExpiredSubscription,
                      ),
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                        height: 1.45,
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
                  valueColor: AppColors.text,
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
                      ? AppColors.accent
                      : freeTripsRemaining > 0
                      ? AppColors.yellow
                      : AppColors.orange,
                  isMonospace: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: 'This month',
                  value: '$tripsUsedThisMonth',
                  valueColor: AppColors.blue,
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
    return CoolCard(
      borderColor: accentColor.withValues(alpha: 0.3),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.45,
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
  const _DriverDetailIntroCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.45,
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

Color _subscriptionStateColor({
  required DriverSubscription? activeSubscription,
  required int freeTripsRemaining,
  required bool hasExpiredSubscription,
}) {
  if (activeSubscription != null) {
    return AppColors.accent;
  }
  if (hasExpiredSubscription || freeTripsRemaining <= 0) {
    return AppColors.orange;
  }
  if (freeTripsRemaining < 5) {
    return AppColors.yellow;
  }
  return AppColors.blue;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
