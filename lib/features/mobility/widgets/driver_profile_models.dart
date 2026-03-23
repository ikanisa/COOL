import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/identity/public_user_identity.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../models/trip.dart';

/// Local display model for the driver profile screen.
class DriverProfileData {
  const DriverProfileData({
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
  final VehicleData vehicle;
  final List<ScheduledTripData> scheduledTrips;
  final DriverSubscription? subscription;

  String get initials {
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  DriverSubscription? activeSubscription(DateTime now) {
    if (subscription == null) return null;
    if (subscription!.expiresAt.isAfter(now)) return subscription;
    return null;
  }

  bool shouldShowUpgradeBanner(DateTime now) {
    final hasExpiredSubscription =
        subscription != null && !subscription!.expiresAt.isAfter(now);
    return hasExpiredSubscription || freeTripsRemaining < 5;
  }

  DriverProfileData copyWith({VehicleData? vehicle, bool? isOnline}) {
    return DriverProfileData(
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

class VehicleData {
  const VehicleData({
    required this.type,
    required this.plateNumber,
    required this.baseLocation,
    required this.status,
  });

  final String type;
  final String plateNumber;
  final String baseLocation;
  final String status;

  bool get hasType => _hasVisibleValue(type);

  bool get hasPlateNumber => _hasVisibleValue(plateNumber);

  bool get hasBaseLocation => _hasVisibleValue(baseLocation);

  bool get isVerified {
    final normalized = status.toLowerCase();
    return normalized.contains('online') ||
        normalized.contains('verified') ||
        normalized.contains('approved') ||
        normalized.contains('active');
  }

  /// Returns the PNG asset path for the vehicle type icon.
  String get iconPath => tripVehicleIcon(type);

  Color statusColor(BuildContext context) {
    final colors = context.coolSemanticColors;
    final normalized = status.toLowerCase();
    if (isVerified) {
      return colors.success;
    }
    if (normalized.contains('offline')) {
      return colors.neutral;
    }
    if (normalized.contains('pending')) return colors.warning;
    if (normalized.contains('maintenance')) return colors.warning;
    return colors.info;
  }

  static bool _hasVisibleValue(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed != '--';
  }
}

class ScheduledTripData {
  const ScheduledTripData({
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

  factory ScheduledTripData.fromTrip(Trip trip) {
    return ScheduledTripData(
      fromLocation: trip.fromLocation,
      toLocation: trip.toLocation,
      departureTime: trip.departureTime,
      vehicleLabel: trip.vehicleType,
      isReturnTrip: trip.isReturn || trip.isDriverReturnTrip,
      isRecurring: trip.isRecurring,
    );
  }
}

class DriverSubscription {
  const DriverSubscription({
    required this.plan,
    required this.startedAt,
    required this.expiresAt,
  });

  final SubscriptionPlan plan;
  final DateTime startedAt;
  final DateTime expiresAt;
}

// ── Formatting helpers ────────────────────────────────────────────────

String formatAmount(int amount) {
  return NumberFormat.decimalPattern('en_US').format(amount);
}

String formatDate(DateTime date) {
  return DateFormat('d MMM yyyy').format(date);
}

String formatTripDate(DateTime date) {
  return DateFormat('EEE d MMM · HH:mm').format(date);
}

String shortDriverId(String? value) {
  return PublicUserIdentity.resolve(publicUserId: value, fallback: '000000');
}

String displayValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? '--' : trimmed;
}

String tripVehicleIcon(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return 'assets/icons/vehicle_moto.png';
  if (normalized.contains('cab') || normalized.contains('car')) {
    return 'assets/icons/vehicle_cab.png';
  }
  if (normalized.contains('truck')) return 'assets/icons/vehicle_truck.png';
  if (normalized.contains('pickup') || normalized.contains('others')) {
    return 'assets/icons/vehicle_others.png';
  }
  if (normalized.contains('trike') || normalized.contains('van')) {
    return 'assets/icons/vehicle_trike.png';
  }
  return 'assets/icons/vehicle_cab.png';
}
