import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/momo_service.dart';
import '../models/subscription_status.dart';

class SubscriptionRepository {
  SubscriptionRepository({
    required SupabaseClient client,
    required MomoService momoService,
  }) : _client = client,
       _momoService = momoService;

  final SupabaseClient _client;
  final MomoService _momoService;
  static const _monthlyFreeTripQuota = 15;

  Future<SubscriptionStatus> getSubscriptionStatus(String userId) async {
    final tripsUsed = await _safeCountTripsUsed(userId);
    final credits = await _safeLoadFreeTripsRemaining(
      userId,
      tripsUsed: tripsUsed,
    );

    dynamic row;
    try {
      row = await _client
          .from('driver_subscriptions')
          .select()
          .eq('driver_id', userId)
          .order('expires_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } on PostgrestException catch (error) {
      if (!_isRecoverableSchemaMismatch(error)) {
        rethrow;
      }
    }

    if (row == null) {
      return SubscriptionStatus.freeTier(
        driverId: userId,
        tripsUsed: tripsUsed,
      ).copyWith(tripsRemaining: credits);
    }

    final status = SubscriptionStatus.fromJson(<String, dynamic>{
      ..._asMap(row),
      'trips_used': tripsUsed,
      'trips_remaining': _isActive(row['status']) ? -1 : credits,
    });

    return status.copyWith(tripsRemaining: status.isSubscribed ? -1 : credits);
  }

  Future<void> initiateSubscription(String userId, String plan) async {
    await _momoService.initiateSubscription(
      driverId: userId,
      plan: _planFromId(plan),
    );
  }

  Future<int> checkTripsRemaining(String userId) async {
    final status = await getSubscriptionStatus(userId);
    return status.isSubscribed ? -1 : status.tripsRemaining;
  }

  Future<int> _safeCountTripsUsed(String userId) async {
    try {
      return await _countTripsUsed(userId);
    } on PostgrestException catch (error) {
      if (!_isRecoverableSchemaMismatch(error)) {
        rethrow;
      }
      return 0;
    }
  }

  Future<int> _countTripsUsed(String userId) async {
    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month);
    final nextPeriodStart = DateTime(now.year, now.month + 1);

    final rows = await _client
        .from('mobility_trips')
        .select('id')
        .eq('user_id', userId)
        .gte('created_at', periodStart.toIso8601String())
        .lt('created_at', nextPeriodStart.toIso8601String());

    return rows.length;
  }

  Future<int> _safeLoadFreeTripsRemaining(
    String userId, {
    required int tripsUsed,
  }) async {
    try {
      return await _loadFreeTripsRemaining(userId, tripsUsed: tripsUsed);
    } on PostgrestException catch (error) {
      if (!_isRecoverableSchemaMismatch(error)) {
        rethrow;
      }
      final remaining = _monthlyFreeTripQuota - tripsUsed;
      return remaining > 0 ? remaining : 0;
    }
  }

  Future<int> _loadFreeTripsRemaining(
    String userId, {
    required int tripsUsed,
  }) async {
    final row = await _client
        .from('driver_profiles')
        .select('trips_used_this_month')
        .eq('user_id', userId)
        .maybeSingle();

    final recordedTripsUsed = _asInt(
      row == null ? tripsUsed : row['trips_used_this_month'],
    );
    final remaining = _monthlyFreeTripQuota - recordedTripsUsed;
    return remaining > 0 ? remaining : 0;
  }
}

SubscriptionPlan _planFromId(String planId) {
  switch (planId) {
    case 'moto_taxi':
    case 'moto':
      return MomoService.motoTaxiPlan;
    case 'cab_other':
    case 'cab':
    case 'other':
      return MomoService.cabOtherPlan;
    default:
      throw ArgumentError.value(
        planId,
        'planId',
        'Unknown MOMO subscription plan.',
      );
  }
}

bool _isActive(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'active';
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

bool _isRecoverableSchemaMismatch(PostgrestException error) {
  final normalized = [
    error.code,
    error.message,
    error.details,
    error.hint,
  ].whereType<String>().join(' ').toLowerCase();

  return error.code == 'PGRST202' ||
      error.code == 'PGRST205' ||
      error.code == '42703' ||
      error.code == '42P01' ||
      normalized.contains('does not exist') ||
      normalized.contains('could not find') ||
      normalized.contains('column') ||
      normalized.contains('relation');
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Expected a JSON object but received ${value.runtimeType}.');
}
