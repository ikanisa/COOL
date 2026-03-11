import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/engagement_providers.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/performance_service.dart';
import '../providers/mobility_provider.dart';
import '../repositories/trip_repository.dart';

final tripSyncServiceProvider = Provider<TripSyncService>((ref) {
  final repository = ref.watch(mobilityTripRepositoryProvider);
  final crashlytics = ref.read(crashlyticsServiceProvider);
  final performance = ref.read(performanceServiceProvider);
  return TripSyncService(
    repository: repository,
    crashlytics: crashlytics,
    performance: performance,
  );
});

class TripSyncService {
  TripSyncService({
    required TripRepository repository,
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
  }) : _repository = repository,
       _crashlytics = crashlytics,
       _performance = performance;

  final TripRepository _repository;
  final CrashlyticsService _crashlytics;
  final PerformanceService _performance;

  Future<TripSyncSummary>? _inFlight;

  Future<TripSyncSummary> syncPendingTrips({
    required String userId,
    required String source,
  }) {
    final activeSync = _inFlight;
    if (activeSync != null) {
      return activeSync;
    }

    final future = _runSync(userId: userId, source: source);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<TripSyncSummary> _runSync({
    required String userId,
    required String source,
  }) async {
    _performance.startTrace('mobility_sync_pending_trips');
    await _crashlytics.log('mobility: syncing pending trips source=$source');

    try {
      final summary = await _repository.syncPendingTrips(userId: userId);
      await _performance.stopTrace(
        'mobility_sync_pending_trips',
        metrics: {
          'pending': summary.pendingCount,
          'synced': summary.syncedCount,
          'failed': summary.failedCount,
          'discarded': summary.discardedCount,
        },
        attributes: {'source': source},
      );
      return summary;
    } catch (error, stack) {
      await _performance.stopTrace(
        'mobility_sync_pending_trips',
        attributes: {'source': source, 'error': error.runtimeType.toString()},
      );
      await _crashlytics.recordError(
        error,
        stackTrace: stack,
        reason: 'mobility_sync_pending_trips',
      );
      rethrow;
    }
  }
}
